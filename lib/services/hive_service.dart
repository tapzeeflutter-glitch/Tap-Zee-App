import 'package:hive_flutter/hive_flutter.dart';
import 'package:tapzee/models/user_profile.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/models/attendance.dart';
import 'package:tapzee/models/message.dart';

class HiveService {
  static Future<void> init() async {
    await Hive.openBox<UserProfile>('userProfiles');
    await Hive.openBox<Room>('rooms');
    await Hive.openBox<Attendance>('attendance');
    await Hive.openBox<Message>('messages');
  }

  // UserProfile operations
  static Box<UserProfile> getUserProfileBox() =>
      Hive.box<UserProfile>('userProfiles');
  static Future<void> saveUserProfile(UserProfile profile) async =>
      await getUserProfileBox().put(profile.uid, profile);
  static UserProfile? getUserProfile(String uid) =>
      getUserProfileBox().get(uid);

  // Room operations
  static Box<Room> getRoomBox() => Hive.box<Room>('rooms');
  static Future<void> saveRoom(Room room) async =>
      await getRoomBox().put(room.id, room);
  static Room? getRoom(String id) => getRoomBox().get(id);
  static List<Room> getAllRooms() => getRoomBox().values.toList();

  // Attendance operations
  static Box<Attendance> getAttendanceBox() =>
      Hive.box<Attendance>('attendance');
  static Future<void> saveAttendance(Attendance attendance) async =>
      await getAttendanceBox().put(attendance.id, attendance);
  static List<Attendance> getAttendanceForRoom(String roomId) =>
      getAttendanceBox().values.where((a) => a.roomId == roomId).toList();

  // Message operations
  static Box<Message> getMessageBox() => Hive.box<Message>('messages');
  static Future<void> saveMessage(Message message) async =>
      await getMessageBox().add(message); // Hive handles auto-incrementing key
  static List<Message> getMessagesForRoom(String roomId) => getMessageBox()
      .values
      .where((m) => m.text.contains(roomId))
      .toList(); // Simplified for now

  static Future<void> close() async {
    await Hive.close();
  }
}
