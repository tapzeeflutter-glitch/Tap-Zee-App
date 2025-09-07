import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tapzee/models/message.dart';
import 'package:tapzee/services/hive_service.dart';
import 'package:tapzee/services/spam_detection_service.dart';

class RealtimeChatService {
  static final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://tap-zee-default-rtdb.firebaseio.com/',
  );
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache for active listeners
  static final Map<String, StreamSubscription> _listeners = {};
  static final Map<String, List<Message>> _messageCache = {};

  /// Send a message to a room using Realtime Database
  static Future<void> sendMessage({
    required String roomId,
    required String text,
    String? fileUrl,
    String? fileName,
    bool enforceSpamFilter = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Run spam detection before sending. If the detector flags the message
    // as spam, do not send it to the realtime database.
    if (enforceSpamFilter) {
      try {
        final SpamResult spamRes = await SpamDetectionService.checkSpam(text);
        print(spamRes);
        if (spamRes.isSpam) {
          print(
            'RealtimeChatService: Message blocked by spam detector (confidence=${spamRes.confidence})',
          );
          throw Exception(
            'Message blocked by spam detector (confidence: ${spamRes.confidence}%)',
          );
        }
      } catch (e) {
        // If the spam service itself fails unexpectedly, log and continue
        // (spam service is designed to fail-open). We do not want to block
        // sending due to detector errors.
        print('RealtimeChatService: spam detection failed: $e');
      }
    }

    final messageRef = _database.ref('chats/$roomId/messages').push();
    final messageId = messageRef.key!;

    final message = Message(
      id: messageId,
      senderId: user.uid,
      senderDisplayName: user.displayName ?? 'Unknown',
      senderEmail: user.email ?? '',
      text: text,
      timestamp: Timestamp.now(),
      fileUrl: fileUrl,
      fileName: fileName,
    );

    final messageData = message.toMap();
    // Convert Timestamp to milliseconds for Realtime Database
    messageData['timestamp'] = message.timestamp.millisecondsSinceEpoch;

    try {
      // Send to Realtime Database for real-time updates (PRIORITY)
      await messageRef.set(messageData);

      // Update local cache immediately for instant UI update
      _updateLocalCache(roomId, message);

      // Do other operations in background (non-blocking)
      _performBackgroundOperations(roomId, message);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  /// Perform background operations that don't block message sending
  static void _performBackgroundOperations(String roomId, Message message) {
    // Run all background operations asynchronously
    Timer.run(() async {
      try {
        // These operations run in parallel, not blocking the UI
        await Future.wait([
          // Save to local Hive cache
          HiveService.saveMessage(message),
          // Update room metadata
          _updateRoomMetadata(roomId, message),
          // Optional: Save to Firestore backup (kept enabled to maintain backups)
          _saveToFirestoreBackup(roomId, message),
        ]);
      } catch (e) {
        print('Background operations failed: $e');
        // Don't throw error as message is already sent
      }
    });
  }

  /// Listen to messages for a specific room with real-time updates
  static Stream<List<Message>> getMessagesStream(
    String roomId, {
    int limit = 50,
  }) {
    final controller = StreamController<List<Message>>.broadcast();

    // Return cached messages immediately if available
    if (_messageCache.containsKey(roomId) &&
        _messageCache[roomId]!.isNotEmpty) {
      controller.add(_messageCache[roomId]!);
    }

    // Set up real-time listener
    final messagesRef = _database
        .ref('chats/$roomId/messages')
        .orderByChild('timestamp')
        .limitToLast(limit);

    final subscription = messagesRef.onValue.listen(
      (event) async {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) {
          controller.add([]);
          return;
        }

        final messages = <Message>[];
        for (final entry in data.entries) {
          try {
            final messageData = Map<String, dynamic>.from(entry.value);
            // Convert timestamp back to Timestamp object
            final timestampMs = messageData['timestamp'] as int;
            messageData['timestamp'] = Timestamp.fromMillisecondsSinceEpoch(
              timestampMs,
            );
            messageData['id'] = entry.key;

            final message = Message.fromMap(messageData);
            messages.add(message);
          } catch (e) {
            print('Error parsing message: $e');
          }
        }

        // Sort messages by timestamp (newest first)
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        // Update cache
        _messageCache[roomId] = messages;

        // Save to Hive for offline access
        for (final message in messages) {
          await HiveService.saveMessage(message);
        }

        controller.add(messages);
      },
      onError: (error) {
        print('Error listening to messages: $error');
        controller.addError(error);
      },
    );

    // Store subscription for cleanup
    _listeners[roomId] = subscription;

    // Cleanup when stream is cancelled
    controller.onCancel = () {
      subscription.cancel();
      _listeners.remove(roomId);
    };

    return controller.stream;
  }

  /// Load older messages (pagination)
  static Future<List<Message>> loadOlderMessages(
    String roomId,
    Message lastMessage, {
    int limit = 20,
  }) async {
    try {
      final messagesRef = _database
          .ref('chats/$roomId/messages')
          .orderByChild('timestamp')
          .endBefore(lastMessage.timestamp.millisecondsSinceEpoch)
          .limitToLast(limit);

      final snapshot = await messagesRef.get();
      final data = snapshot.value as Map<dynamic, dynamic>?;

      if (data == null) return [];

      final messages = <Message>[];
      for (final entry in data.entries) {
        try {
          final messageData = Map<String, dynamic>.from(entry.value);
          final timestampMs = messageData['timestamp'] as int;
          messageData['timestamp'] = Timestamp.fromMillisecondsSinceEpoch(
            timestampMs,
          );
          messageData['id'] = entry.key;

          final message = Message.fromMap(messageData);
          messages.add(message);
        } catch (e) {
          print('Error parsing older message: $e');
        }
      }

      // Sort messages by timestamp (newest first)
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Save to Hive for offline access
      for (final message in messages) {
        await HiveService.saveMessage(message);
      }

      return messages;
    } catch (e) {
      print('Error loading older messages: $e');
      return [];
    }
  }

  /// Update room's last message and activity
  static Future<void> _updateRoomMetadata(
    String roomId,
    Message message,
  ) async {
    try {
      final roomRef = _database.ref('chats/$roomId/metadata');
      await roomRef.update({
        'lastMessage': message.text,
        'lastMessageTime': message.timestamp.millisecondsSinceEpoch,
        'lastMessageSender': message.senderEmail,
        'messageCount': 1, // Will be updated properly with database rules
      });
    } catch (e) {
      print('Error updating room metadata: $e');
    }
  }

  /// Backup messages to Firestore for analytics and long-term storage
  static Future<void> _saveToFirestoreBackup(
    String roomId,
    Message message,
  ) async {
    try {
      await _firestore
          .collection('rooms')
          .doc(roomId)
          .collection('messages')
          .doc(message.id)
          .set(message.toMap());
    } catch (e) {
      print('Error backing up to Firestore: $e');
      // Don't throw error as this is optional backup
    }
  }

  /// Update local message cache
  static void _updateLocalCache(String roomId, Message message) {
    if (!_messageCache.containsKey(roomId)) {
      _messageCache[roomId] = [];
    }

    // Add message to beginning of list (newest first)
    _messageCache[roomId]!.insert(0, message);

    // Keep cache size reasonable (max 100 messages)
    if (_messageCache[roomId]!.length > 100) {
      _messageCache[roomId] = _messageCache[roomId]!.take(100).toList();
    }
  }

  /// Get cached messages for offline viewing
  static List<Message> getCachedMessages(String roomId) {
    return _messageCache[roomId] ?? [];
  }

  /// Delete a message (admin only)
  static Future<void> deleteMessage(String roomId, String messageId) async {
    try {
      await _database.ref('chats/$roomId/messages/$messageId').remove();

      // Also remove from Firestore backup
      await _firestore
          .collection('rooms')
          .doc(roomId)
          .collection('messages')
          .doc(messageId)
          .delete();

      // Remove from local cache
      if (_messageCache.containsKey(roomId)) {
        _messageCache[roomId]!.removeWhere((msg) => msg.id == messageId);
      }
    } catch (e) {
      throw Exception('Failed to delete message: $e');
    }
  }

  /// Get room activity/metadata
  static Stream<Map<String, dynamic>?> getRoomActivityStream(String roomId) {
    return _database.ref('chats/$roomId/metadata').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      return data?.cast<String, dynamic>();
    });
  }

  /// Mark user as typing
  static Future<void> setTypingStatus(String roomId, bool isTyping) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final typingRef = _database.ref('chats/$roomId/typing/${user.uid}');

      if (isTyping) {
        await typingRef.set({
          'userEmail': user.email,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        // Auto-remove typing status after 3 seconds
        Timer(const Duration(seconds: 3), () {
          typingRef.remove();
        });
      } else {
        await typingRef.remove();
      }
    } catch (e) {
      print('Error setting typing status: $e');
    }
  }

  /// Get typing users stream
  static Stream<List<String>> getTypingUsersStream(String roomId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _database.ref('chats/$roomId/typing').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <String>[];

      final typingUsers = <String>[];
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final entry in data.entries) {
        final userData = Map<String, dynamic>.from(entry.value);
        final timestamp = userData['timestamp'] as int;
        final userEmail = userData['userEmail'] as String;
        final displayName = userData['displayName'] as String? ?? userEmail;

        // Only include users who typed in the last 5 seconds and aren't current user
        if (now - timestamp < 5000 && userEmail != user.email) {
          typingUsers.add(displayName);
        }
      }

      return typingUsers;
    });
  }

  /// Clean up resources
  static void dispose() {
    for (final subscription in _listeners.values) {
      subscription.cancel();
    }
    _listeners.clear();
    _messageCache.clear();
  }

  /// Clean up specific room listener
  static void disposeRoom(String roomId) {
    _listeners[roomId]?.cancel();
    _listeners.remove(roomId);
    _messageCache.remove(roomId);
  }

  /// Initialize user presence
  static Future<void> initializeUserPresence(String roomId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final presenceRef = _database.ref('chats/$roomId/presence/${user.uid}');

      // Set user as online
      await presenceRef.set({
        'userEmail': user.email,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'online': true,
      });

      // Set user as offline when disconnected
      await presenceRef.onDisconnect().update({
        'online': false,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('Error initializing presence: $e');
    }
  }

  /// Get online users count
  static Stream<int> getOnlineUsersCountStream(String roomId) {
    return _database.ref('chats/$roomId/presence').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return 0;

      int onlineCount = 0;
      for (final entry in data.entries) {
        final userData = Map<String, dynamic>.from(entry.value);
        if (userData['online'] == true) {
          onlineCount++;
        }
      }
      return onlineCount;
    });
  }
}
