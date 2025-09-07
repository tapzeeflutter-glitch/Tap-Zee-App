import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0)
  final String uid;
  @HiveField(1)
  final String email;
  @HiveField(2)
  String? name;
  @HiveField(3)
  int? age;
  @HiveField(4)
  String? photoUrl;

  UserProfile({
    required this.uid,
    required this.email,
    this.name,
    this.age,
    this.photoUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'age': age,
      'photoUrl': photoUrl,
    };
  }

  static UserProfile fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] as String,
      email: map['email'] as String,
      name: map['name'] as String?,
      age: map['age'] as int?,
      photoUrl: map['photoUrl'] as String?,
    );
  }
}
