import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tapzee/models/user_profile.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/models/attendance.dart';
import 'package:tapzee/models/message.dart';
import 'package:tapzee/services/hive_service.dart';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream subscription for connectivity changes
  StreamSubscription? _connectivitySubscription;

  SyncService() {
    _listenToConnectivityChanges();
  }

  void _listenToConnectivityChanges() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        // If connectivity is restored, attempt to sync
        print('Connectivity restored, attempting sync...');
        syncAllData();
      }
    });
  }

  Future<void> syncAllData() async {
    print('Starting full data sync...');
    final user = _auth.currentUser;
    if (user == null) {
      print('No user logged in, skipping sync.');
      return;
    }

    await _syncUserProfiles();
    await _syncRooms();
    await _syncAttendance();
    await _syncMessages();
    print('Full data sync complete.');
  }

  Future<void> _syncUserProfiles() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Upload local profile changes to Firestore
    final localProfile = HiveService.getUserProfile(user.uid);
    if (localProfile != null) {
      print('Uploading local user profile...');
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(localProfile.toMap(), SetOptions(merge: true));
    }

    // Download latest profile from Firestore to local Hive
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      print('Downloading remote user profile...');
      final remoteProfile = UserProfile.fromMap(doc.data()!);
      await HiveService.saveUserProfile(remoteProfile);
    }
  }

  Future<void> _syncRooms() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Upload local new/updated rooms to Firestore
    final localRooms = HiveService.getAllRooms();
    for (var room in localRooms) {
      // Check if room exists remotely or if it's a newer version locally
      final remoteRoomDoc = await _firestore
          .collection('rooms')
          .doc(room.id)
          .get();
      if (!remoteRoomDoc.exists ||
          (remoteRoomDoc.exists &&
              room.createdAt.toDate().isAfter(
                Room.fromMap(remoteRoomDoc.data()!).createdAt.toDate(),
              ))) {
        print('Uploading local room: ${room.name}');
        await _firestore.collection('rooms').doc(room.id).set(room.toMap());
      }
    }

    // Download new/updated rooms from Firestore to local Hive
    final querySnapshot = await _firestore.collection('rooms').get();
    for (var doc in querySnapshot.docs) {
      final remoteRoom = Room.fromMap(doc.data());
      final localRoom = HiveService.getRoom(remoteRoom.id);

      if (localRoom == null ||
          remoteRoom.createdAt.toDate().isAfter(localRoom.createdAt.toDate())) {
        print('Downloading remote room: ${remoteRoom.name}');
        await HiveService.saveRoom(remoteRoom);
      }
    }
  }

  Future<void> _syncAttendance() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Upload local attendance records to Firestore
    final localAttendance = HiveService.getAttendanceBox().values.toList();
    for (var record in localAttendance) {
      // Check if record exists remotely or if it's a newer version locally
      final remoteAttendanceDoc = await _firestore
          .collection('attendance')
          .doc(record.id)
          .get();
      if (!remoteAttendanceDoc.exists) {
        print('Uploading local attendance record: ${record.id}');
        await _firestore
            .collection('attendance')
            .doc(record.id)
            .set(record.toMap());
      }
    }

    // Download attendance records from Firestore to local Hive
    final querySnapshot = await _firestore.collection('attendance').get();
    for (var doc in querySnapshot.docs) {
      final remoteRecord = Attendance.fromMap(doc.data());
      final localRecord = HiveService.getAttendanceBox().get(remoteRecord.id);
      if (localRecord == null) {
        // Only download if not exists locally for now
        print('Downloading remote attendance record: ${remoteRecord.id}');
        await HiveService.saveAttendance(remoteRecord);
      }
    }
  }

  Future<void> _syncMessages() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Upload local messages to Firestore
    // This can be complex, as messages are per-room. A simpler approach for now:
    // Assume messages are pushed to Firestore immediately when sent. Offline messages can be stored and sent when online.
    // For this sync service, we'll focus on downloading existing messages.

    // Download messages from Firestore to local Hive
    final rooms = HiveService.getAllRooms();
    for (var room in rooms) {
      final querySnapshot = await _firestore
          .collection('rooms')
          .doc(room.id)
          .collection('messages')
          .get();
      for (var doc in querySnapshot.docs) {
        final remoteMessage = Message.fromMap(doc.data());
        // Check if message already exists in Hive. This requires a unique ID for messages.
        // For now, we will add all messages to Hive. In a real app, you'd want to check if it already exists.
        final messageExists = HiveService.getMessageBox().values.any(
          (msg) =>
              msg.senderId == remoteMessage.senderId &&
              msg.timestamp ==
                  remoteMessage
                      .timestamp && // Simple equality for unique message
              msg.text == remoteMessage.text,
        );

        if (!messageExists) {
          print(
            'Downloading remote message for room ${room.name}: ${remoteMessage.text}',
          );
          await HiveService.saveMessage(remoteMessage);
        }
      }
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
