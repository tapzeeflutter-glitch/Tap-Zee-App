import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'room.g.dart';

@HiveType(typeId: 1)
class Room extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String description;
  @HiveField(3)
  final String adminUid;
  @HiveField(4)
  final GeoPoint location;
  @HiveField(5)
  final double radius;
  @HiveField(6)
  final List<String> approvedMembers;
  @HiveField(7)
  final List<String> pendingMembers;
  @HiveField(8)
  final List<String> rules;
  @HiveField(9)
  final Timestamp createdAt;
  @HiveField(10)
  final List<String> blockedMembers; // Add this field

  Room({
    required this.id,
    required this.name,
    required this.description,
    required this.adminUid,
    required this.location,
    required this.radius,
    this.approvedMembers = const [],
    this.pendingMembers = const [],
    this.rules = const [],
    required this.createdAt,
    this.blockedMembers = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'adminUid': adminUid,
      'location': location,
      'radius': radius,
      'approvedMembers': approvedMembers,
      'pendingMembers': pendingMembers,
      'rules': rules,
      'createdAt': createdAt,
      'blockedMembers': blockedMembers,
    };
  }

  static Room fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      adminUid: map['adminUid'] as String,
      location: map['location'] as GeoPoint,
      radius: map['radius'] as double,
      approvedMembers: List<String>.from(map['approvedMembers'] ?? []),
      pendingMembers: List<String>.from(map['pendingMembers'] ?? []),
      rules: List<String>.from(map['rules'] ?? []),
      createdAt: map['createdAt'] as Timestamp,
      blockedMembers: List<String>.from(map['blockedMembers'] ?? []),
    );
  }

  static Room fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return Room.fromMap(data);
  }
}
