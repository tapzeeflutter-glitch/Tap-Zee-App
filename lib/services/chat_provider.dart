import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tapzee/models/room.dart';

class ChatProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Room> _rooms = [];
  int _unreadCount = 0;

  List<Room> get rooms => _rooms;
  int get unreadCount => _unreadCount;

  ChatProvider() {
    _listenRooms();
  }

  /// Manual refresh trigger to re-fetch rooms and unread counts.
  /// Useful for UI refresh buttons.
  Future<void> refreshRooms() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snapshot = await _firestore.collection('rooms').get();
      final List<Room> loadedRooms = snapshot.docs
          .map((doc) => Room.fromFirestore(doc))
          .toList();

      int unread = 0;
      for (final room in loadedRooms) {
        final messagesSnap = await _firestore
            .collection('rooms')
            .doc(room.id)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();
        if (messagesSnap.docs.isNotEmpty) {
          final msgData = messagesSnap.docs.first.data();
          if (msgData['senderUid'] != user.uid) {
            unread++;
          }
        }
      }

      _rooms = loadedRooms;
      _unreadCount = unread;
      notifyListeners();
    } catch (e) {
      // ignore errors for manual refresh to avoid crashing UI
      print('ChatProvider.refreshRooms error: $e');
    }
  }

  void _listenRooms() {
    _firestore.collection('rooms').snapshots().listen((snapshot) async {
      final user = _auth.currentUser;
      if (user == null) return;
      final List<Room> loadedRooms = snapshot.docs
          .map((doc) => Room.fromFirestore(doc))
          .toList();
      int unread = 0;
      for (final room in loadedRooms) {
        final messagesSnap = await _firestore
            .collection('rooms')
            .doc(room.id)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();
        if (messagesSnap.docs.isNotEmpty) {
          final msgData = messagesSnap.docs.first.data();
          if (msgData['senderUid'] != user.uid) {
            unread++;
          }
        }
      }
      _rooms = loadedRooms;
      _unreadCount = unread;
      notifyListeners();
    });
  }
}
