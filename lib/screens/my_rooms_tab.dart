import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/screens/room_detail_screen.dart';
import 'package:tapzee/screens/room_chat_screen.dart';
import 'dart:async';
import 'package:tapzee/services/user_location_service.dart';
import 'package:tapzee/widgets/user_marker_widget.dart';

class MyRoomsTab extends StatefulWidget {
  const MyRoomsTab({super.key});

  @override
  State<MyRoomsTab> createState() => _MyRoomsTabState();
}

class _MyRoomsTabState extends State<MyRoomsTab> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in to view your rooms'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Rooms',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () {
                  // Refresh rooms
                  setState(() {});
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('rooms')
                  .where('adminUid', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.meeting_room_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No rooms created yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create your first room to get started',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                final rooms = snapshot.data!.docs
                    .map(
                      (doc) => Room.fromMap(doc.data() as Map<String, dynamic>),
                    )
                    .toList();

                return ListView.builder(
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text(
                            room.name.isNotEmpty
                                ? room.name[0].toUpperCase()
                                : 'R',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          room.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.people,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${room.approvedMembers.length} members',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Icon(
                                  Icons.radio_button_checked,
                                  size: 14,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Only show add members button if user is admin
                            if (room.adminUid == user.uid)
                              IconButton(
                                icon: const Icon(Icons.person_add),
                                onPressed: () => _showAddMembersForRoom(room),
                                tooltip: 'Add Members',
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  RoomDetailScreen(room: room),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Show dialog to add nearby members to the room (copied from RoomChatScreen)
  void _showAddMembersForRoom(Room room) {
    // Use a StreamController + Timer to refresh online users every 30 seconds
    final controller = StreamController<List<AppUser>>();
    Timer? timer;

    // Function to load and add users to the stream
    Future<void> loadUsers() async {
      try {
        final users = await UserLocationService.getAllOnlineUsers();
        if (!controller.isClosed) controller.add(users);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    // Start initial load and periodic timer
    loadUsers();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => loadUsers());

    showDialog(
      context: context,
      builder: (context) => WillPopScope(
        onWillPop: () async {
          // On dialog close, cancel timer and close stream
          timer?.cancel();
          await controller.close();
          return true;
        },
        child: AlertDialog(
          title: const Text('Add Nearby Members'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: StreamBuilder<List<AppUser>>(
              stream: controller.stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final onlineUsers = snapshot.data ?? [];

                // Filter out users who are already members of this room
                final availableUsers = onlineUsers.where((user) {
                  return !room.approvedMembers.contains(user.id) &&
                      !room.pendingMembers.contains(user.id);
                }).toList();

                if (availableUsers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No nearby users available',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'All nearby users are already members',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: availableUsers.length,
                  itemBuilder: (context, index) {
                    final user = availableUsers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: UserMarkerWidget(
                          photoURL: user.photoURL,
                          displayName: user.displayName ?? user.email,
                          isOnline: user.isOnline,
                          size: 30.0,
                        ),
                        title: Text(user.displayName ?? user.email),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.email),
                            const SizedBox(height: 4),
                            Text(
                              'Last seen: ${user.lastSeen}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () {
                            _addUserToRoom(room, user);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          child: const Text('Add'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                timer?.cancel();
                controller.close();
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Ensure resources are cleaned up if dialog closed by other means
      timer?.cancel();
      if (!controller.isClosed) controller.close();
    });
  }

  // Add user to the room (invite)
  Future<void> _addUserToRoom(Room room, AppUser user) async {
    try {
      await _firestore.collection('rooms').doc(room.id).update({
        'pendingMembers': FieldValue.arrayUnion([user.id]),
      });

      // Update local room object and trigger UI update
      setState(() {
        room.pendingMembers.add(user.id);
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close the dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${user.displayName ?? user.email} invited to ${room.name}!',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Show room info dialog (adapted from room_chat_screen)
  void _showRoomInfo(Room room) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(room.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Description: ${room.description}'),
              const SizedBox(height: 8),
              Text('Members: ${room.approvedMembers.length}'),
              const SizedBox(height: 8),
              Text('Pending: ${room.pendingMembers.length}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditRoomDialog(Room room) {
    // TODO: Implement edit room functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit room functionality coming soon')),
    );
  }

  void _showDeleteRoomDialog(Room room) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text(
          'Are you sure you want to delete "${room.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _firestore.collection('rooms').doc(room.id).delete();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Room deleted successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting room: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
