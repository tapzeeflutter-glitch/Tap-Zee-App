import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'message.g.dart';

@HiveType(typeId: 3)
class Message extends HiveObject {
  @HiveField(0)
  final String senderId;
  @HiveField(1)
  final String senderEmail;
  @HiveField(2)
  final String senderDisplayName;
  @HiveField(3)
  final String text;
  @HiveField(4)
  final Timestamp timestamp;
  @HiveField(5)
  final String? fileUrl;
  @HiveField(6)
  final String? fileName;
  @HiveField(7)
  final String? id;

  Message({
    required this.senderId,
    required this.senderEmail,
    required this.senderDisplayName,
    required this.text,
    required this.timestamp,
    this.fileUrl,
    this.fileName,
    this.id,
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderEmail': senderEmail,
      'senderDisplayName': senderDisplayName,
      'text': text,
      'timestamp': timestamp,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'id': id,
    };
  }

  static Message fromMap(Map<String, dynamic> map) {
    return Message(
      senderId: map['senderId'] as String,
      senderEmail: map['senderEmail'] as String,
      senderDisplayName: map['senderDisplayName'] as String? ?? '',
      text: map['text'] as String,
      timestamp: map['timestamp'] as Timestamp,
      fileUrl: map['fileUrl'] as String?,
      fileName: map['fileName'] as String?,
      id: map['id'] as String?,
    );
  }
}
