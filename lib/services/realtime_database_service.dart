import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:tapzee/models/message.dart';

class RealtimeDatabaseService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Messages
  static DatabaseReference getMessagesRef(String roomId) {
    return _database.child('rooms/$roomId/messages');
  }

  static DatabaseReference getMessageRef(String roomId, String messageId) {
    return _database.child('rooms/$roomId/messages/$messageId');
  }

  // Typing indicators
  static DatabaseReference getTypingRef(String roomId) {
    return _database.child('rooms/$roomId/typing');
  }

  static DatabaseReference getUserTypingRef(String roomId, String userId) {
    return _database.child('rooms/$roomId/typing/$userId');
  }

  // Room data
  static DatabaseReference getRoomRef(String roomId) {
    return _database.child('rooms/$roomId');
  }

  static DatabaseReference getRoomMembersRef(String roomId) {
    return _database.child('rooms/$roomId/members');
  }

  // User presence
  static DatabaseReference getUserPresenceRef(String userId) {
    return _database.child('userPresence/$userId');
  }

  // Send message
  static Future<void> sendMessage({
    required String roomId,
    required Message message,
  }) async {
    try {
      final messageId =
          message.id ?? FirebaseDatabase.instance.ref().push().key!;
      await getMessageRef(roomId, messageId).set(message.toMap());
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // Get messages stream
  static Stream<List<Message>> getMessagesStream(String roomId) {
    return getMessagesRef(roomId).orderByChild('timestamp').onValue.map((
      event,
    ) {
      if (event.snapshot.value == null) return [];

      final Map<dynamic, dynamic> data =
          event.snapshot.value as Map<dynamic, dynamic>;

      return data.entries
          .map(
            (entry) => Message.fromMap(
              Map<String, dynamic>.from(entry.value as Map<dynamic, dynamic>),
            ),
          )
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
  }

  // Update typing status
  static Future<void> updateTypingStatus({
    required String roomId,
    required String userId,
    required String displayName,
    required bool isTyping,
  }) async {
    if (isTyping) {
      await getUserTypingRef(
        roomId,
        userId,
      ).set({'displayName': displayName, 'timestamp': ServerValue.timestamp});
    } else {
      await getUserTypingRef(roomId, userId).remove();
    }
  }

  // Get typing users stream
  static Stream<List<String>> getTypingUsersStream(String roomId) {
    return getTypingRef(roomId).onValue.map((event) {
      if (event.snapshot.value == null) return [];

      final Map<dynamic, dynamic> data =
          event.snapshot.value as Map<dynamic, dynamic>;

      return data.entries
          .map((entry) => entry.value['displayName'] as String)
          .toList();
    });
  }

  // Update user presence
  static Future<void> updateUserPresence({
    required String userId,
    required bool isOnline,
  }) async {
    await getUserPresenceRef(
      userId,
    ).set({'isOnline': isOnline, 'lastSeen': ServerValue.timestamp});
  }
}
