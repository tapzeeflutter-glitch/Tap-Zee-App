import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'attendance.g.dart';

@HiveType(typeId: 2)
class Attendance extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String roomId;
  @HiveField(2)
  final String userId;
  @HiveField(3)
  final Timestamp joinTime;
  @HiveField(4)
  Timestamp? leaveTime;

  Attendance({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.joinTime,
    this.leaveTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'roomId': roomId,
      'userId': userId,
      'joinTime': joinTime,
      'leaveTime': leaveTime,
    };
  }

  static Attendance fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'] as String,
      roomId: map['roomId'] as String,
      userId: map['userId'] as String,
      joinTime: map['joinTime'] as Timestamp,
      leaveTime: map['leaveTime'] as Timestamp?,
    );
  }
}
