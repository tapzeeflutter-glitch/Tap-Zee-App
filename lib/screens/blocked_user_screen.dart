import 'package:flutter/material.dart';
import 'package:tapzee/services/spam_detection_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BlockedUserScreen extends StatelessWidget {
  final String roomName;
  final SpamResult spamResult;

  const BlockedUserScreen({
    super.key,
    required this.roomName,
    required this.spamResult,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Blocked'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true, // Show back button
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Block icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.block, size: 80, color: Colors.red.shade700),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                'You have been blocked from "$roomName"',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Reason
              const Text(
                'Your message was detected as spam and you have been automatically blocked from this room.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Detection details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detection Details:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Text('Method: ${spamResult.method}'),
                    // Text(
                    //   'Confidence: ${(spamResult.confidence * 100).toInt()}%',
                    // ),
                    const SizedBox(height: 8),
                    const Text(
                      'If you believe this is an error, please contact the room administrator.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Actions
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Return to Main Screen',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        // Send appeal notification to room admin in Firestore
                        try {
                          final user = await FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'You must be signed in to appeal.',
                                ),
                              ),
                            );
                            return;
                          }
                          // Find the room document by name (ideally use roomId, but using name for now)
                          final roomQuery = await FirebaseFirestore.instance
                              .collection('rooms')
                              .where('name', isEqualTo: roomName)
                              .limit(1)
                              .get();
                          if (roomQuery.docs.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Room not found.')),
                            );
                            return;
                          }
                          final roomDoc = roomQuery.docs.first;
                          // Add appeal request to a subcollection or field for admin
                          await roomDoc.reference.collection('appeals').add({
                            'userId': user.uid,
                            'userName': user.displayName ?? 'Unknown',
                            'timestamp': FieldValue.serverTimestamp(),
                            'reason': 'Blocked by spam detection',
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Appeal sent to room admin.'),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to send appeal: $e'),
                            ),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Appeal Block',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
