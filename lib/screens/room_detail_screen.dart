import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/models/attendance.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RoomDetailScreen extends StatefulWidget {
  final Room room;
  const RoomDetailScreen({super.key, required this.room});
  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  // Show all users' login times (attendance records) in a dialog
  Future<void> _showAttendanceDialog(Room room) async {
    // Show a SnackBar to confirm the button is working
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading attendance records...')),
      );
    }
    try {
      debugPrint('Fetching attendance records for room: ${room.id}');
      final attendanceQuery = await _firestore
          .collection('attendance')
          .where('roomId', isEqualTo: room.id)
          .orderBy('joinTime', descending: true)
          .get();

      debugPrint('Attendance query docs count: ${attendanceQuery.docs.length}');
      final records = attendanceQuery.docs.map((doc) => doc.data()).toList();
      final now = DateTime.now();
      final pastRecords = <Map<String, dynamic>>[];
      final futureRecords = <Map<String, dynamic>>[];
      for (final record in records) {
        final joinTime = record['joinTime'];
        DateTime? dt;
        if (joinTime is Timestamp) {
          dt = joinTime.toDate();
        } else if (joinTime is DateTime) {
          dt = joinTime;
        } else {
          debugPrint('Unknown joinTime type: $joinTime');
        }
        if (dt != null && dt.isAfter(now)) {
          futureRecords.add(record);
        } else {
          pastRecords.add(record);
        }
      }

      debugPrint(
        'Past records: ${pastRecords.length}, Future records: ${futureRecords.length}',
      );

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('User Login Times'),
            content: SizedBox(
              width: 350,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pastRecords.isEmpty)
                      const Text('No attendance records found.')
                    else ...[
                      const Text(
                        'Past Attendance:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(
                        height: 150,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: pastRecords.length,
                          itemBuilder: (context, index) {
                            final record = pastRecords[index];
                            final displayName = record['displayName'];
                            final joinTime = record['joinTime'];
                            DateTime? dt;
                            if (joinTime is Timestamp) {
                              dt = joinTime.toDate();
                            } else if (joinTime is DateTime) {
                              dt = joinTime;
                            } else {
                              debugPrint(
                                'Unknown joinTime type in dialog: $joinTime',
                              );
                            }
                            final formattedTime = dt != null
                                ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                                : 'Unknown';
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(displayName),
                              subtitle: Text('Login: $formattedTime'),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (futureRecords.isNotEmpty) ...[
                      const Text(
                        'Future Scheduled Attendance:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: futureRecords.length,
                          itemBuilder: (context, index) {
                            final record = futureRecords[index];
                            final displayName =
                                record['displayName'] ?? record['userId'] ?? '';
                            final joinTime = record['joinTime'];
                            DateTime? dt;
                            if (joinTime is Timestamp) {
                              dt = joinTime.toDate();
                            } else if (joinTime is DateTime) {
                              dt = joinTime;
                            } else {
                              debugPrint(
                                'Unknown joinTime type in dialog: $joinTime',
                              );
                            }
                            final formattedTime = dt != null
                                ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                                : 'Unknown';
                            return ListTile(
                              leading: const Icon(
                                Icons.person_outline,
                                color: Colors.blue,
                              ),
                              title: Text(displayName),
                              subtitle: Text('Scheduled: $formattedTime'),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e, stack) {
      debugPrint('Error in _showAttendanceDialog: $e\n$stack');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to load attendance records.\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }

  // Upload image to ImageKit and return the public URL
  Future<String?> uploadImageToImageKit(XFile imageFile) async {
    final apiKey = dotenv.env['IMAGEKIT_PUBLIC_API_KEY'] ?? '';
    final uploadPreset = dotenv.env['IMAGEKIT_UPLOAD_PRESET'] ?? '';
    final uploadUrl = 'https://upload.imagekit.io/api/v1/files/upload';
    final fileBytes = await imageFile.readAsBytes();
    final fileBase64 = base64Encode(fileBytes);

    final response = await http.post(
      Uri.parse(uploadUrl),
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode(apiKey + ':'))}',
      },
      body: {
        'file': 'data:image/jpeg;base64,$fileBase64',
        'fileName': 'room_${DateTime.now().millisecondsSinceEpoch}.jpg',
        'publicKey': apiKey,
        'uploadPreset': uploadPreset,
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['url'];
    } else {
      debugPrint('ImageKit upload failed: ${response.body}');
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    dotenv.load();
  }

  // Change room photo (admin only) using Cloudinary
  Future<void> _changeRoomPhoto() async {
    if (_auth.currentUser?.uid != widget.room.adminUid) return;
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile == null) return;

      final photoUrl = await uploadImageToImageKit(pickedFile);
      if (photoUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image to ImageKit.')),
        );
        return;
      }

      await _firestore.collection('rooms').doc(widget.room.id).update({
        'photoUrl': photoUrl,
      });
      setState(() {
        if (widget.room.toMap().containsKey('photoUrl')) {
          widget.room.toMap()['photoUrl'] = photoUrl;
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Room photo updated.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
    }
  }

  // Block user (admin only)
  Future<void> _blockUser(String userId) async {
    if (_auth.currentUser?.uid != widget.room.adminUid) return;
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'blockedMembers': FieldValue.arrayUnion([userId]),
        'approvedMembers': FieldValue.arrayRemove([userId]),
        'pendingMembers': FieldValue.arrayRemove([userId]),
      });
      // Update local model so UI refreshes immediately
      setState(() {
        widget.room.approvedMembers.remove(userId);
        widget.room.pendingMembers.remove(userId);
        if (!widget.room.blockedMembers.contains(userId)) {
          widget.room.blockedMembers.add(userId);
        }
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

  // Unblock user (admin only)
  Future<void> _unblockUser(String userId) async {
    if (_auth.currentUser?.uid != widget.room.adminUid) return;
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'blockedMembers': FieldValue.arrayRemove([userId]),
        'approvedMembers': FieldValue.arrayUnion([userId]),
      });
      // Update local model so UI refreshes immediately
      setState(() {
        if (!widget.room.approvedMembers.contains(userId)) {
          widget.room.approvedMembers.add(userId);
        }
        widget.room.blockedMembers.remove(userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked and approved.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to unblock user: $e')));
    }
  }

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _isJoining = false;
  String? _errorMessage;

  bool get _isAdmin => _auth.currentUser?.uid == widget.room.adminUid;
  bool get _isMember =>
      widget.room.approvedMembers.contains(_auth.currentUser?.uid);
  bool get _isPending =>
      widget.room.pendingMembers.contains(_auth.currentUser?.uid);

  // ...existing code...

  Future<void> _sendJoinRequest() async {
    if (_auth.currentUser == null) {
      setState(() {
        _errorMessage = 'You must be logged in to join a room.';
      });
      return;
    }
    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'pendingMembers': FieldValue.arrayUnion([_auth.currentUser!.uid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request sent successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send join request.';
      });
      debugPrint('Error sending join request: $e');
    } finally {
      setState(() {
        _isJoining = false;
      });
    }
  }

  Future<void> _approveMember(String memberUid) async {
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'pendingMembers': FieldValue.arrayRemove([memberUid]),
        'approvedMembers': FieldValue.arrayUnion([memberUid]),
      });
      final attendanceId = _firestore.collection('attendance').doc().id;
      final attendanceRecord = Attendance(
        id: attendanceId,
        roomId: widget.room.id,
        userId: memberUid,
        joinTime: Timestamp.now(),
      );
      await _firestore
          .collection('attendance')
          .doc(attendanceId)
          .set(attendanceRecord.toMap());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member approved.')));
      }
      // Update local model so UI refreshes immediately
      setState(() {
        widget.room.pendingMembers.remove(memberUid);
        if (!widget.room.approvedMembers.contains(memberUid)) {
          widget.room.approvedMembers.add(memberUid);
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to approve member.';
      });
      debugPrint('Error approving member: $e');
    }
  }

  Future<void> _rejectMember(String memberUid) async {
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'pendingMembers': FieldValue.arrayRemove([memberUid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member rejected.')));
      }
      // Update local model so UI refreshes immediately
      setState(() {
        widget.room.pendingMembers.remove(memberUid);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to reject member.';
      });
      debugPrint('Error rejecting member: $e');
    }
  }

  Future<void> _removeMember(String memberUid) async {
    try {
      await _firestore.collection('rooms').doc(widget.room.id).update({
        'approvedMembers': FieldValue.arrayRemove([memberUid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member removed.')));
      }
      // Update local model so UI refreshes immediately
      setState(() {
        widget.room.approvedMembers.remove(memberUid);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to remove member.';
      });
      debugPrint('Error removing member: $e');
    }
  }

  void _confirmDeleteRoom(Room room) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: const Text(
          'Are you sure you want to delete this room? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _firestore.collection('rooms').doc(room.id).delete();
                Navigator.pop(context);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                setState(() {
                  _errorMessage = 'Failed to delete room.';
                });
                debugPrint('Error deleting room: $e');
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditRoomDialog(Room room) {
    final nameController = TextEditingController(text: room.name);
    final descController = TextEditingController(text: room.description);
    final radiusController = TextEditingController(
      text: room.radius.toString(),
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Room Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Room Name'),
              ),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: radiusController,
                decoration: const InputDecoration(labelText: 'Radius (meters)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _firestore.collection('rooms').doc(room.id).update({
                  'name': nameController.text,
                  'description': descController.text,
                  'radius':
                      double.tryParse(radiusController.text) ?? room.radius,
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Room Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 16),
            if (!_isAdmin && !_isMember && !_isPending)
              ElevatedButton(
                onPressed: _isJoining ? null : _sendJoinRequest,
                child: _isJoining
                    ? const CircularProgressIndicator()
                    : const Text('Request to Join'),
              ),
            if (_isPending) const Chip(label: Text('Join Request Pending')),
            if (_isMember && !_isAdmin)
              const Chip(label: Text('You are a member')),

            if (_isAdmin) ...[
              Text(
                'Admin Panel',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Room Info'),
                    onPressed: () => _showEditRoomDialog(widget.room),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
              const SizedBox(height: 16),
              Text('Members', style: Theme.of(context).textTheme.titleMedium),
              // Build a combined unique list of member UIDs preserving admin first
              Builder(
                builder: (context) {
                  final adminUid = widget.room.adminUid;
                  final allUids = <String>{};
                  // Ensure admin is first in the list
                  if (adminUid.isNotEmpty) allUids.add(adminUid);
                  for (final uid in widget.room.approvedMembers) {
                    if (uid != adminUid) allUids.add(uid);
                  }
                  for (final uid in widget.room.pendingMembers) {
                    if (uid != adminUid) allUids.add(uid);
                  }
                  for (final uid in widget.room.blockedMembers) {
                    if (uid != adminUid) allUids.add(uid);
                  }
                  final uidList = allUids.toList();
                  if (uidList.isEmpty) return const Text('No members yet.');
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: uidList.length,
                    itemBuilder: (context, index) {
                      final memberUid = uidList[index];
                      final isAdmin = memberUid == adminUid;
                      final isApproved = widget.room.approvedMembers.contains(
                        memberUid,
                      );
                      final isPending = widget.room.pendingMembers.contains(
                        memberUid,
                      );
                      final isBlocked = widget.room.blockedMembers.contains(
                        memberUid,
                      );
                      // Load basic user document for richer UI
                      return FutureBuilder<DocumentSnapshot>(
                        future: _firestore
                            .collection('users')
                            .doc(memberUid)
                            .get(),
                        builder: (context, userSnapshot) {
                          if (userSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const ListTile(title: Text('Loading...'));
                          }
                          if (userSnapshot.hasError ||
                              !userSnapshot.hasData ||
                              !userSnapshot.data!.exists) {
                            // Fallback to UID display if user doc not available
                            return ListTile(
                              leading: isAdmin
                                  ? const CircleAvatar(
                                      child: Icon(
                                        Icons.admin_panel_settings,
                                        color: Colors.blue,
                                      ),
                                    )
                                  : const CircleAvatar(
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.grey,
                                      ),
                                    ),
                              title: Text(memberUid),
                              subtitle: Text('User data not available'),
                              trailing: _buildStatusActions(
                                memberUid,
                                isAdmin,
                                isApproved,
                                isPending,
                                isBlocked,
                              ),
                            );
                          }
                          final userData =
                              userSnapshot.data!.data()
                                  as Map<String, dynamic>? ??
                              {};
                          final name =
                              userData['displayName'] ??
                              userData['name'] ??
                              userData['email'] ??
                              'Unknown User';
                          final email = userData['email'] ?? '';
                          final photoUrl =
                              userData['photoUrl'] ?? userData['photoURL'];
                          return ListTile(
                            leading:
                                photoUrl != null &&
                                    (photoUrl as String).isNotEmpty
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(photoUrl),
                                    radius: 22,
                                  )
                                : CircleAvatar(
                                    child: isAdmin
                                        ? const Icon(
                                            Icons.admin_panel_settings,
                                            color: Colors.blue,
                                          )
                                        : const Icon(
                                            Icons.person,
                                            color: Colors.grey,
                                          ),
                                    radius: 22,
                                  ),
                            title: Text(name),
                            subtitle: Text(email),
                            trailing: _buildStatusActions(
                              memberUid,
                              isAdmin,
                              isApproved,
                              isPending,
                              isBlocked,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('Show All Users Login Times'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => _showAttendanceDialog(widget.room),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete),
                label: const Text('Delete Room'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () => _confirmDeleteRoom(widget.room),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Build trailing widget showing status icon and admin actions when applicable
  Widget _buildStatusActions(
    String memberUid,
    bool memberIsAdmin,
    bool isApproved,
    bool isPending,
    bool isBlocked,
  ) {
    // Status icon
    Icon statusIcon;
    if (memberIsAdmin) {
      statusIcon = const Icon(Icons.admin_panel_settings, color: Colors.blue);
    } else if (isPending) {
      statusIcon = const Icon(Icons.hourglass_top, color: Colors.amber);
    } else if (isApproved) {
      statusIcon = const Icon(Icons.check_circle, color: Colors.green);
    } else {
      statusIcon = const Icon(Icons.person, color: Colors.grey);
    }

    final children = <Widget>[statusIcon];

    // If current user is the room admin, show action buttons for non-admin members
    if (_isAdmin && !memberIsAdmin) {
      if (isPending) {
        children.addAll([
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            tooltip: 'Approve member',
            onPressed: () => _approveMember(memberUid),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: 'Reject member',
            onPressed: () => _rejectMember(memberUid),
          ),
        ]);
      } else if (isBlocked) {
        children.add(
          IconButton(
            icon: const Icon(Icons.lock_open, color: Colors.green),
            tooltip: 'Unblock',
            onPressed: () => _unblockUser(memberUid),
          ),
        );
      } else {
        children.addAll([
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.red),
            tooltip: 'Remove member',
            onPressed: () => _removeMember(memberUid),
          ),
          // Only show Block button if not blocked
          IconButton(
            icon: const Icon(Icons.block, color: Colors.orange),
            tooltip: 'Block',
            onPressed: () => _blockUser(memberUid),
          ),
        ]);
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
