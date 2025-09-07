import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/models/message.dart';
import 'package:tapzee/screens/blocked_user_screen.dart';
import 'package:tapzee/services/user_location_service.dart';
import 'package:tapzee/services/spam_detection_service.dart';
import 'package:tapzee/services/chat_optimization_service.dart';
import 'package:tapzee/services/realtime_chat_service.dart';
import 'package:tapzee/widgets/user_marker_widget.dart';
import 'package:path_provider/path_provider.dart';

class RoomChatScreen extends StatefulWidget {
  final Room room;

  const RoomChatScreen({super.key, required this.room});

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  final _messageController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  List<Message> _messages = []; // Use Message model
  String? _errorMessage;
  List<DocumentSnapshot> _pendingRooms = [];
  bool _isLoadingOlderMessages = false;
  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<List<String>>? _typingSubscription;
  List<String> _typingUsers = [];
  Timer? _typingTimer;

  Timer? _pendingRoomsTimer;
  // Note: _heldMessages removed since we now block users immediately for spam

  @override
  void initState() {
    super.initState();
    _setupOptimizedChatListeners();
    _checkPendingRoomRequests();
    _fetchPendingRooms();

    // Auto-refresh pending rooms every 30 seconds
    _pendingRoomsTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _fetchPendingRooms();
    });

    // Initialize user presence for real-time features
    RealtimeChatService.initializeUserPresence(widget.room.id);

    // Start periodic cache optimization
    ChatOptimizationService.startPeriodicOptimization();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _pendingRoomsTimer?.cancel();
    _messagesSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();

    // Cleanup chat optimization resources
    ChatOptimizationService.clearRoomCache(widget.room.id);
    ChatOptimizationService.stopPeriodicOptimization();

    super.dispose();
  }

  Future<void> _setupOptimizedChatListeners() async {
    // Listen to optimized message stream
    _messagesSubscription =
        ChatOptimizationService.getOptimizedMessagesStream(
          widget.room.id,
        ).listen(
          (messages) {
            if (mounted) {
              setState(() {
                _messages = messages;
              });
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage = 'Error loading messages: $error';
              });
            }
          },
        );

    // Listen to typing indicators
    _typingSubscription =
        RealtimeChatService.getTypingUsersStream(widget.room.id).listen((
          typingUsers,
        ) {
          if (mounted) {
            setState(() {
              _typingUsers = typingUsers;
            });
          }
        });
  }

  // Check if current user has pending room requests and show modal
  Future<void> _checkPendingRoomRequests() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Query rooms where user is in pendingMembers
    final query = await _firestore
        .collection('rooms')
        .where('pendingMembers', arrayContains: user.uid)
        .get();

    if (query.docs.isNotEmpty) {
      for (final doc in query.docs) {
        final roomData = doc.data();
        final roomName = roomData['name'] ?? 'Room';
        final roomId = doc.id;

        // Show modal for each pending room
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Room Invitation'),
              content: Text('You have been invited to join "$roomName".'),
              actions: [
                TextButton(
                  onPressed: () async {
                    // Accept: move user from pendingMembers to approvedMembers
                    await _firestore.collection('rooms').doc(roomId).update({
                      'pendingMembers': FieldValue.arrayRemove([user.uid]),
                      'approvedMembers': FieldValue.arrayUnion([user.uid]),
                    });
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('You joined $roomName!')),
                    );
                  },
                  child: const Text('Accept'),
                ),
                TextButton(
                  onPressed: () async {
                    // Decline: remove user from pendingMembers
                    await _firestore.collection('rooms').doc(roomId).update({
                      'pendingMembers': FieldValue.arrayRemove([user.uid]),
                    });
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Request declined.')),
                    );
                  },
                  child: const Text('Decline'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  // Fetch rooms where current user is in pendingMembers
  Future<void> _fetchPendingRooms() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final query = await _firestore
        .collection('rooms')
        .where('pendingMembers', arrayContains: user.uid)
        .get();
    setState(() {
      _pendingRooms = query.docs;
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'You must be logged in to send messages.';
      });
      return;
    }

    final messageText = _messageController.text.trim();
    final senderDisplayName = user.displayName ?? user.email ?? '';

    // Quick spam check before sending
    try {
      final spamResult = await SpamDetectionService.checkSpam(messageText);

      if (spamResult.isSpam) {
        // Clear the input field if spam detected
        _messageController.clear();
        // Block the user in Firestore (add to blockedMembers)
        await _firestore.collection('rooms').doc(widget.room.id).update({
          'blockedMembers': FieldValue.arrayUnion([user.uid]),
          'approvedMembers': FieldValue.arrayRemove([user.uid]),
          'pendingMembers': FieldValue.arrayRemove([user.uid]),
        });
        // Block the user locally as well
        if (widget.room.approvedMembers.contains(user.uid)) {
          widget.room.approvedMembers.remove(user.uid);
        }
        if (widget.room.pendingMembers.contains(user.uid)) {
          widget.room.pendingMembers.remove(user.uid);
        }
        // Show spam warning dialog, then redirect after dialog is closed
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Spam Detected',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your message was blocked because it appears to be spam.',
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Confidence: ${(spamResult.confidence.toDouble() * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please ensure your message is relevant and not promotional.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK', style: TextStyle(color: Colors.blue)),
                ),
              ],
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BlockedUserScreen(
                roomName: widget.room.name,
                spamResult: spamResult,
              ),
            ),
          );
        }
        return; // Block the message and stop execution
      }
    } catch (e) {
      // If spam detection fails, log but allow message to proceed
      print('Spam detection failed: $e');
    }

    // Clear the input after spam check passes
    _messageController.clear();

    try {
      // Send message with optimistic UI updates
      await ChatOptimizationService.sendOptimizedMessage(
        roomId: widget.room.id,
        text: messageText,
        senderDisplayName: senderDisplayName,
      );

      // --- Attendance record creation ---
      try {
        final attendanceQuery = await _firestore
            .collection('attendance')
            .where('roomId', isEqualTo: widget.room.id)
            .where('userId', isEqualTo: user.uid)
            .limit(1)
            .get();

        if (attendanceQuery.docs.isEmpty) {
          final attendanceId = _firestore.collection('attendance').doc().id;
          await _firestore.collection('attendance').doc(attendanceId).set({
            'id': attendanceId,
            'roomId': widget.room.id,
            'userId': user.uid,
            'displayName': user.displayName,
            'joinTime': Timestamp.now(),
          });
        }
      } catch (e) {
        print('Failed to create attendance record: $e');
      }
      // --- End attendance record creation ---

      setState(() {
        _errorMessage = null;
      });

      // Clear typing indicator
      RealtimeChatService.setTypingStatus(widget.room.id, false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send message: $e';
      });
      // Restore the message text if sending failed
      _messageController.text = messageText;
    }
  }

  Future<void> _sendFile() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'You must be logged in to share files.';
      });
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        final fileExtension = fileName.split('.').last.toLowerCase();

        String fileUrlToSend;
        String messageText = 'Shared a file:';

        // Check if it's an image or PDF file for base64 encoding
        if (_isImageFileExtension(fileExtension) || fileExtension == 'pdf') {
          try {
            // Convert to base64 for images and PDFs
            final bytes = await file.readAsBytes();
            final base64String = base64Encode(bytes);

            String mimeType;
            if (fileExtension == 'pdf') {
              mimeType = 'application/pdf';
              messageText = 'Shared a PDF:';
            } else if (fileExtension == 'png') {
              mimeType = 'image/png';
              messageText = 'Shared an image:';
            } else if (fileExtension == 'jpg' || fileExtension == 'jpeg') {
              mimeType = 'image/jpeg';
              messageText = 'Shared an image:';
            } else if (fileExtension == 'gif') {
              mimeType = 'image/gif';
              messageText = 'Shared an image:';
            } else if (fileExtension == 'webp') {
              mimeType = 'image/webp';
              messageText = 'Shared an image:';
            } else {
              mimeType = 'application/octet-stream';
            }

            fileUrlToSend = 'data:$mimeType;base64,$base64String';
          } catch (e) {
            print(
              'Failed to encode file as base64, falling back to Firebase Storage: $e',
            );
            // Fallback to Firebase Storage if base64 encoding fails
            String filePath =
                'room_files/${widget.room.id}/${user.uid}/${fileName}';
            UploadTask uploadTask = _storage
                .ref()
                .child(filePath)
                .putFile(file);
            TaskSnapshot snapshot = await uploadTask;
            fileUrlToSend = await snapshot.ref.getDownloadURL();
          }
        } else {
          // For other file types, upload to Firebase Storage
          String filePath =
              'room_files/${widget.room.id}/${user.uid}/${fileName}';
          UploadTask uploadTask = _storage.ref().child(filePath).putFile(file);
          TaskSnapshot snapshot = await uploadTask;
          fileUrlToSend = await snapshot.ref.getDownloadURL();
        }

        // Use optimized chat service for sending file messages
        await ChatOptimizationService.sendOptimizedMessage(
          roomId: widget.room.id,
          text: messageText,
          senderDisplayName: user.displayName ?? user.email ?? '',
          fileUrl: fileUrlToSend,
          fileName: fileName,
        );

        setState(() {
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload file: $e';
      });
    }
  }

  void _launchUrl(String url) async {
    await _launchUrlInternal(url, external: false);
  }

  Future<void> _launchUrlInternal(String url, {bool external = false}) async {
    try {
      Uri uri;

      // Normalize common local file path patterns to file:// URIs
      // If the url looks like an absolute file path (Windows drive letter or starting with '/'),
      // or already starts with 'file://', treat it as a file path.
      final lower = url.toLowerCase();
      final windowsDrive = RegExp(r'^[a-z]:\\|^[a-z]:/');

      if (lower.startsWith('file://') ||
          windowsDrive.hasMatch(url) ||
          url.startsWith('/')) {
        // Use Uri.file so platform-specific encoding is correct
        uri = Uri.file(url);
      } else {
        uri = Uri.parse(url);
      }

      // Try launching; some platforms may not report canLaunchUrl
      bool canLaunch = false;
      try {
        canLaunch = await canLaunchUrl(uri);
      } catch (inner) {
        // Some platforms throw for unsupported schemes; we'll attempt launch anyway
        print('canLaunchUrl threw: $inner for uri: $uri');
      }

      if (canLaunch) {
        await launchUrl(
          uri,
          mode: external
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault,
        );
        return;
      }

      // If canLaunch reported false, still try a direct launch for file URIs as a fallback
      if (!canLaunch && uri.scheme == 'file') {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        } catch (inner) {
          print('launchUrl fallback for file failed: $inner');
        }
      }
    } catch (e, st) {
      print('Failed to launch url: $url  error: $e\n$st');
    }

    if (!mounted) return;
    setState(() {
      _errorMessage = 'Could not launch $url';
    });
  }

  /// Open a file link. If it's an embedded data URL, write to temp file first.
  Future<void> _openFile(String url, String fileName) async {
    try {
      print('Opening file: $fileName with URL: $url');

      if (url.startsWith('data:')) {
        // data:<mime>;base64,<data>
        final idx = url.indexOf(',');
        if (idx <= 0) throw Exception('Invalid data URL');
        final meta = url.substring(5, idx); // e.g. image/png;base64
        final mime = meta.split(';').first;
        final base64Part = url.substring(idx + 1);
        final bytes = base64Decode(base64Part);

        // Support images and PDFs by writing a temp file and launching it.
        String ext;
        if (mime == 'image/png') {
          ext = 'png';
        } else if (mime == 'image/jpeg') {
          ext = 'jpg';
        } else if (mime == 'image/gif') {
          ext = 'gif';
        } else if (mime == 'image/webp') {
          ext = 'webp';
        } else if (mime == 'application/pdf') {
          ext = 'pdf';
        } else {
          // not supported
          if (mounted) {
            setState(() {
              _errorMessage = 'Embedded file type not supported: $mime';
            });
          }
          return;
        }

        final dir = await getTemporaryDirectory();
        final baseName = fileName.contains('.')
            ? fileName.split('.').first
            : fileName;
        final safeBase = baseName.replaceAll(RegExp(r"[^A-Za-z0-9_.-]"), '_');
        final outPath = '${dir.path}/$safeBase.$ext';
        final outFile = File(outPath);
        await outFile.writeAsBytes(bytes, flush: true);

        print('Temp file created at: $outPath');

        // Use open_filex to open the file
        final result = await OpenFilex.open(outPath);
        print('OpenFilex result: ${result.type}, ${result.message}');

        if (result.type == ResultType.done) {
          print('File opened successfully');
        } else {
          throw Exception('Failed to open file: ${result.message}');
        }
        return;
      }

      // For Firebase Storage URLs or other remote URLs
      if (url.startsWith('http')) {
        try {
          // For remote files, we need to download them first to open with open_filex
          print('Downloading file from URL: $url');

          // Create a temporary file
          final dir = await getTemporaryDirectory();
          final baseName = fileName.contains('.')
              ? fileName.split('.').first
              : fileName;
          final extension = fileName.contains('.')
              ? fileName.split('.').last
              : 'tmp';
          final safeBase = baseName.replaceAll(RegExp(r"[^A-Za-z0-9_.-]"), '_');
          final tempPath = '${dir.path}/$safeBase.$extension';

          // Download the file
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final response = await request.close();

          if (response.statusCode == 200) {
            final file = File(tempPath);
            await response.pipe(file.openWrite());
            print('File downloaded to: $tempPath');

            // Use open_filex to open the downloaded file
            final result = await OpenFilex.open(tempPath);
            print('OpenFilex result: ${result.type}, ${result.message}');

            if (result.type == ResultType.done) {
              print('File opened successfully');
            } else {
              throw Exception('Failed to open file: ${result.message}');
            }
          } else {
            throw Exception(
              'Failed to download file: HTTP ${response.statusCode}',
            );
          }

          httpClient.close();
          return;
        } catch (e) {
          print('Failed to download and open file: $e');
          // Fallback to URL launcher
          final uri = Uri.parse(url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      // For local file paths
      final result = await OpenFilex.open(url);
      print('OpenFilex result: ${result.type}, ${result.message}');

      if (result.type == ResultType.done) {
        print('File opened successfully');
      } else {
        throw Exception('Failed to open file: ${result.message}');
      }
    } catch (e) {
      print('Failed to open file: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to open file: $e';
        });

        // Show error dialog with more details
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error Opening File'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Could not open: $fileName'),
                const SizedBox(height: 8),
                Text('Error: $e'),
                const SizedBox(height: 8),
                const Text(
                  'Make sure you have an app installed that can open this file type.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  bool _isDataUrl(String url) {
    return url.startsWith('data:');
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http') &&
        (lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.gif') ||
            lower.endsWith('.webp'));
  }

  bool _isImageFileName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  bool _isImageFileExtension(String extension) {
    final lower = extension.toLowerCase();
    return lower == 'png' ||
        lower == 'jpg' ||
        lower == 'jpeg' ||
        lower == 'gif' ||
        lower == 'webp';
  }

  bool _isPdfFileName(String name) {
    return name.toLowerCase().endsWith('.pdf');
  }

  bool _isPdfUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http') && lower.endsWith('.pdf');
  }

  Widget _fileLinkTile(String fileName, String url, bool isMe) {
    // Determine the appropriate icon based on file type
    IconData fileIcon;
    Color iconColor = isMe ? Colors.white : Colors.blue.shade900;

    if (_isPdfFileName(fileName) || _isPdfUrl(url)) {
      fileIcon = Icons.picture_as_pdf;
      iconColor = isMe ? Colors.white : Colors.red.shade700;
    } else if (_isImageFileName(fileName) || _isImageUrl(url)) {
      fileIcon = Icons.image;
      iconColor = isMe ? Colors.white : Colors.green.shade700;
    } else {
      fileIcon = Icons.attachment;
    }

    return GestureDetector(
      onTap: () => _openFile(url, fileName),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue.shade700 : Colors.blue.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fileIcon, color: iconColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.blue.shade900,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show dialog to add nearby members to the room
  void _showAddMembersDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Nearby Members'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder<List<AppUser>>(
            future: UserLocationService.getAllOnlineUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final onlineUsers = snapshot.data ?? [];

              // Filter out users who are already members of this room
              final availableUsers = onlineUsers.where((user) {
                return !widget.room.approvedMembers.contains(user.id) &&
                    !widget.room.pendingMembers.contains(user.id);
              }).toList();

              if (availableUsers.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No nearby users available',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'All nearby users are already members',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: availableUsers.length,
                itemBuilder: (context, index) {
                  final user = availableUsers[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: UserMarkerWidget(
                        photoURL: user.photoURL,
                        displayName: user.displayName ?? user.email,
                        isOnline: user.isOnline,
                        size: 30.0,
                      ),
                      title: Text(user.displayName ?? user.email),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.email),
                          const SizedBox(height: 4),
                          Text(
                            'Last seen: ${_formatDateTime(user.lastSeen)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          _addUserToRoom(user);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: const Text('Add'),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Add user to the room
  Future<void> _addUserToRoom(AppUser user) async {
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'pendingMembers': FieldValue.arrayUnion([user.id]),
      });

      // Update local room object and trigger UI update
      setState(() {
        widget.room.pendingMembers.add(user.id);
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close the dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${user.displayName ?? user.email} invited to ${widget.room.name}!',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Add user removal and block function for admin only
  Future<void> _removeUserFromRoom(String userId) async {
    // Only admin can remove users
    if (_auth.currentUser?.uid != widget.room.adminUid) return;

    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'approvedMembers': FieldValue.arrayRemove([userId]),
        'pendingMembers': FieldValue.arrayRemove([userId]),
      });
      setState(() {
        widget.room.approvedMembers.remove(userId);
        widget.room.pendingMembers.remove(userId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User removed from room.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove user: $e')));
    }
  }

  // (Removed unused _blockCurrentUser method)

  Future<void> _blockUser(String userId) async {
    // Only admin can block users
    if (_auth.currentUser?.uid != widget.room.adminUid) return;

    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'blockedMembers': FieldValue.arrayUnion([userId]),
        'approvedMembers': FieldValue.arrayRemove([userId]),
        'pendingMembers': FieldValue.arrayRemove([userId]),
      });
      setState(() {
        widget.room.approvedMembers.remove(userId);
        widget.room.pendingMembers.remove(userId);
        // Optionally update a local blockedMembers list if you use one
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User blocked from room.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to block user: $e')));
    }
  }

  // Add unblock request function
  Future<void> _requestUnblock(String userId) async {
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'unblockRequests': FieldValue.arrayUnion([userId]),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unblock request sent to admin.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send unblock request: $e')),
      );
    }
  }

  // Show room info dialog
  void _showRoomInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.room.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Description: ${widget.room.description}'),
              const SizedBox(height: 8),
              Text('Members: ${widget.room.approvedMembers.length}'),
              const SizedBox(height: 8),
              const Text(
                'Admin:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // Show admin details
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.room.adminUid)
                    .get(),
                builder: (context, adminSnapshot) {
                  if (adminSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Text('Loading admin details...');
                  }
                  if (adminSnapshot.hasError ||
                      !adminSnapshot.hasData ||
                      !adminSnapshot.data!.exists) {
                    return const Text('Admin details unavailable');
                  }
                  final adminData =
                      adminSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                  final adminName =
                      adminData['displayName'] ?? widget.room.adminUid;
                  final adminEmail = adminData['email'] ?? '';
                  return Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundImage:
                                adminData['photoURL'] != null &&
                                    adminData['photoURL'].isNotEmpty
                                ? NetworkImage(adminData['photoURL'])
                                : null,
                            child:
                                (adminData['photoURL'] == null ||
                                    adminData['photoURL'].isEmpty)
                                ? Icon(
                                    Icons.person,
                                    size: 32,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  adminName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                if (adminEmail.isNotEmpty)
                                  Text(
                                    adminEmail,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Show pending member details
              FutureBuilder<List<DocumentSnapshot>>(
                future: Future.wait(
                  widget.room.pendingMembers.map(
                    (uid) => FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .get(),
                  ),
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading pending requests...');
                  }
                  if (snapshot.hasError) {
                    return Text('Error loading pending users');
                  }
                  final docs = snapshot.data ?? [];
                  if (docs.isEmpty) {
                    return const Text('No pending requests');
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Pending Requests:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text('${widget.room.pendingMembers.length}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: docs.map((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final displayName = data['displayName'];

                          final email = data['email'] ?? '';
                          final photoUrl = data['photoURL'] ?? data['photoUrl'];

                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              width: 220,
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundImage:
                                        photoUrl != null && photoUrl.isNotEmpty
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child:
                                        (photoUrl == null || photoUrl.isEmpty)
                                        ? Icon(
                                            Icons.person,
                                            size: 28,
                                            color: Colors.grey,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (email.isNotEmpty)
                                          Text(
                                            email,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),

              Text(
                'Created: ${_formatDateTime(widget.room.createdAt.toDate())}',
              ),
              const SizedBox(height: 8),
              if (widget.room.adminUid == _auth.currentUser?.uid)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Approved Members:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(' ${widget.room.approvedMembers.length}'),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Format DateTime for display
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    // Use a fallback for blockedMembers if not present in Room model
    final blockedMembers = (widget.room as dynamic).blockedMembers ?? [];
    final isBlocked = blockedMembers.contains(user?.uid);

    if (isBlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BlockedUserScreen(
              roomName: widget.room.name,
              spamResult: SpamResult(isSpam: true, confidence: 1.0),
            ),
          ),
        );
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.name),
        actions: [
          if (widget.room.adminUid == _auth.currentUser?.uid)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: _showAddMembersDialog,
              tooltip: 'Add Members',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'room_info') {
                _showRoomInfo();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'room_info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Text('Room Info'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.red,
              child: Center(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          // ...pending rooms UI...
          if (_pendingRooms.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: _pendingRooms.map((doc) {
                  final roomData = doc.data() as Map<String, dynamic>;
                  final roomName = roomData['name'] ?? 'Room';
                  final roomDesc = roomData['description'] ?? '';
                  return ListTile(
                    title: Text(roomName),
                    subtitle: Text(roomDesc),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await _firestore
                                .collection('rooms')
                                .doc(doc.id)
                                .update({
                                  'pendingMembers': FieldValue.arrayRemove([
                                    user!.uid,
                                  ]),
                                  'approvedMembers': FieldValue.arrayUnion([
                                    user.uid,
                                  ]),
                                });
                            _fetchPendingRooms();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('You joined $roomName!')),
                            );
                          },
                          child: const Text('Accept'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _firestore
                                .collection('rooms')
                                .doc(doc.id)
                                .update({
                                  'pendingMembers': FieldValue.arrayRemove([
                                    user!.uid,
                                  ]),
                                });
                            _fetchPendingRooms();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Request declined.')),
                            );
                          },
                          child: const Text('Decline'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet. Start the conversation!',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadOlderMessages,
                          child: ListView.builder(
                            reverse: true,
                            itemCount:
                                _messages.length +
                                (_isLoadingOlderMessages ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_isLoadingOlderMessages &&
                                  index == _messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final message = _messages[index];
                              final isMe =
                                  message.senderId == _auth.currentUser?.uid;

                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Align(
                                  alignment: isMe
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Column(
                                    crossAxisAlignment: isMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (!isMe)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          child: Text(
                                            message.senderDisplayName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      Container(
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.7,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? Colors.blue.shade600
                                              : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              message.text,
                                              style: TextStyle(
                                                color: isMe
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                            if (message.fileUrl != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: Builder(
                                                  builder: (context) {
                                                    final url =
                                                        message.fileUrl!;

                                                    if (_isDataUrl(url)) {
                                                      try {
                                                        final idx = url.indexOf(
                                                          ',',
                                                        );
                                                        final meta = url.substring(
                                                          5,
                                                          idx,
                                                        ); // e.g. image/png;base64 or application/pdf;base64
                                                        final mime = meta
                                                            .split(';')
                                                            .first;
                                                        final base64Part = url
                                                            .substring(idx + 1);
                                                        final bytes =
                                                            base64Decode(
                                                              base64Part,
                                                            );

                                                        // Handle PDF data URLs
                                                        if (mime ==
                                                            'application/pdf') {
                                                          return GestureDetector(
                                                            onTap: () =>
                                                                _openFile(
                                                                  url,
                                                                  message
                                                                      .fileName!,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    12,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: isMe
                                                                    ? Colors
                                                                          .blue
                                                                          .shade700
                                                                    : Colors
                                                                          .red
                                                                          .shade50,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                border: Border.all(
                                                                  color: isMe
                                                                      ? Colors
                                                                            .white
                                                                      : Colors
                                                                            .red
                                                                            .shade300,
                                                                ),
                                                              ),
                                                              child: Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Icon(
                                                                    Icons
                                                                        .picture_as_pdf,
                                                                    color: isMe
                                                                        ? Colors
                                                                              .white
                                                                        : Colors
                                                                              .red
                                                                              .shade700,
                                                                    size: 32,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 12,
                                                                  ),
                                                                  Flexible(
                                                                    child: Column(
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children: [
                                                                        Text(
                                                                          message
                                                                              .fileName!,
                                                                          style: TextStyle(
                                                                            color:
                                                                                isMe
                                                                                ? Colors.white
                                                                                : Colors.red.shade700,
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                          ),
                                                                        ),
                                                                        Text(
                                                                          'PDF Document',
                                                                          style: TextStyle(
                                                                            color:
                                                                                isMe
                                                                                ? Colors.white70
                                                                                : Colors.red.shade600,
                                                                            fontSize:
                                                                                12,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        }

                                                        // Handle image data URLs
                                                        return GestureDetector(
                                                          onTap: () =>
                                                              _openFile(
                                                                url,
                                                                message
                                                                    .fileName!,
                                                              ),
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            child: Image.memory(
                                                              bytes,
                                                              width: 220,
                                                              fit: BoxFit.cover,
                                                            ),
                                                          ),
                                                        );
                                                      } catch (e) {
                                                        return _fileLinkTile(
                                                          message.fileName!,
                                                          url,
                                                          isMe,
                                                        );
                                                      }
                                                    }

                                                    // Handle regular URLs
                                                    final isImageByName =
                                                        message.fileName !=
                                                            null &&
                                                        _isImageFileName(
                                                          message.fileName!,
                                                        );
                                                    final isPdfByName =
                                                        message.fileName !=
                                                            null &&
                                                        _isPdfFileName(
                                                          message.fileName!,
                                                        );

                                                    if (_isPdfUrl(url) ||
                                                        isPdfByName) {
                                                      return GestureDetector(
                                                        onTap: () => _openFile(
                                                          url,
                                                          message.fileName!,
                                                        ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: isMe
                                                                ? Colors
                                                                      .blue
                                                                      .shade700
                                                                : Colors
                                                                      .red
                                                                      .shade50,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            border: Border.all(
                                                              color: isMe
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .red
                                                                        .shade300,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .picture_as_pdf,
                                                                color: isMe
                                                                    ? Colors
                                                                          .white
                                                                    : Colors
                                                                          .red
                                                                          .shade700,
                                                                size: 32,
                                                              ),
                                                              const SizedBox(
                                                                width: 12,
                                                              ),
                                                              Flexible(
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Text(
                                                                      message
                                                                          .fileName!,
                                                                      style: TextStyle(
                                                                        color:
                                                                            isMe
                                                                            ? Colors.white
                                                                            : Colors.red.shade700,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                    ),
                                                                    Text(
                                                                      'PDF Document',
                                                                      style: TextStyle(
                                                                        color:
                                                                            isMe
                                                                            ? Colors.white70
                                                                            : Colors.red.shade600,
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    }

                                                    if (_isImageUrl(url) ||
                                                        isImageByName) {
                                                      return GestureDetector(
                                                        onTap: () => _openFile(
                                                          url,
                                                          message.fileName!,
                                                        ),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          child: Image.network(
                                                            url,
                                                            width: 220,
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (
                                                                  c,
                                                                  err,
                                                                  st,
                                                                ) => _fileLinkTile(
                                                                  message
                                                                      .fileName!,
                                                                  url,
                                                                  isMe,
                                                                ),
                                                          ),
                                                        ),
                                                      );
                                                    }

                                                    return _fileLinkTile(
                                                      message.fileName!,
                                                      url,
                                                      isMe,
                                                    );
                                                  },
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${message.timestamp.toDate().hour}:${message.timestamp.toDate().minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
                _buildTypingIndicator(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _sendFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'Enter message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (text) {
                      _onTextChanged(text);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  mini: true,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Handle text change for typing indicators
  void _onTextChanged(String text) {
    if (text.trim().isEmpty) {
      RealtimeChatService.setTypingStatus(widget.room.id, false);
      _typingTimer?.cancel();
    } else {
      RealtimeChatService.setTypingStatus(widget.room.id, true);

      // Auto-stop typing indicator after 3 seconds of no typing
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        RealtimeChatService.setTypingStatus(widget.room.id, false);
      });
    }
  }

  /// Load older messages when scrolling up
  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlderMessages || _messages.isEmpty) return;

    setState(() {
      _isLoadingOlderMessages = true;
    });

    try {
      final olderMessages = await ChatOptimizationService.loadOlderMessages(
        widget.room.id,
        lastMessage: _messages.last,
      );

      if (mounted && olderMessages.isNotEmpty) {
        setState(() {
          _messages.addAll(olderMessages);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading older messages: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOlderMessages = false;
        });
      }
    }
  }

  /// Build typing indicator widget
  Widget _buildTypingIndicator() {
    if (_typingUsers.isEmpty) return const SizedBox.shrink();

    // _typingUsers now contains display names
    String typingText;
    if (_typingUsers.length == 1) {
      typingText = '${_typingUsers.first} is typing...';
    } else if (_typingUsers.length == 2) {
      typingText = '${_typingUsers.first} and ${_typingUsers[1]} are typing...';
    } else {
      typingText = '${_typingUsers.length} people are typing...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue.shade300,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            typingText,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
