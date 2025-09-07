import 'package:provider/provider.dart';
import 'package:tapzee/screens/blocked_user_screen.dart';
import 'package:tapzee/services/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/screens/room_chat_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tapzee/services/spam_detection_service.dart';

class ChatsTab extends StatefulWidget {
  final ValueChanged<int>? onUnreadCountChanged;
  const ChatsTab({super.key, this.onUnreadCountChanged});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  // Cache for admin display names
  final Map<String, String> _adminNameCache = {};

  // Fetch admin display name from Firestore if not present in room data
  Future<String> fetchAdminDisplayName(String adminUid) async {
    if (_adminNameCache.containsKey(adminUid)) {
      return _adminNameCache[adminUid]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(adminUid)
          .get();
      final name = doc.data()?['displayName'] ?? adminUid;
      _adminNameCache[adminUid] = name;
      return name;
    } catch (e) {
      return adminUid;
    }
  }
  // Removed unused _auth field
  // Provider-based, no manual Firestore or state needed

  // Add a stub for _showAddMembersForRoom to avoid undefined error
  void _showAddMembersForRoom(Room room) {
    // TODO: Implement add members functionality
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Add members for ${room.name}')));
  }

  // Move chatListBuilder outside of _fetchBlockedRooms
  Widget chatListBuilder(List<Room> rooms) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final user = FirebaseAuth.instance.currentUser;
        final allRooms = chatProvider.rooms;
        // Only show rooms where the current user is an approved member
        final approvedRooms = allRooms.where((r) {
          try {
            return r.approvedMembers.contains(user?.uid);
          } catch (_) {
            return false;
          }
        }).toList();

        // Blocked rooms: user is in blockedMembers
        final blockedRooms = allRooms.where((r) {
          try {
            return r.blockedMembers != null &&
                r.blockedMembers.contains(user?.uid);
          } catch (_) {
            return false;
          }
        }).toList();

        return ListView(
          children: [
            if (blockedRooms.isNotEmpty)
              Container(
                color: Colors.red[100],
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Text(
                        'Blocked Rooms',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    ...blockedRooms.map((room) {
                      String lastMessage = '';
                      String? avatarUrl;
                      if (room.toMap().containsKey('lastMessage')) {
                        lastMessage = room.toMap()['lastMessage'] ?? '';
                      }
                      if (room.toMap().containsKey('photoUrl')) {
                        avatarUrl = room.toMap()['photoUrl'];
                      } else if (room.toMap().containsKey('imageUrl')) {
                        avatarUrl = room.toMap()['imageUrl'];
                      }
                      final adminDisplayName =
                          room.toMap()['adminDisplayName'] ??
                          room.toMap()['adminName'];
                      return FutureBuilder<String>(
                        future: adminDisplayName != null
                            ? Future.value(adminDisplayName)
                            : fetchAdminDisplayName(room.adminUid),
                        builder: (context, snapshot) {
                          final adminName = snapshot.data ?? room.adminUid;
                          return Card(
                            color: const Color.fromARGB(255, 236, 229, 229),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: CircleAvatar(
                                radius: 26,
                                backgroundColor: Colors.red[400],
                                backgroundImage:
                                    avatarUrl != null && avatarUrl.isNotEmpty
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                    ? Text(
                                        room.name.isNotEmpty
                                            ? room.name[0].toUpperCase()
                                            : 'R',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                room.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.red,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  lastMessage.isNotEmpty
                                      ? Text(
                                          lastMessage,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 12,
                                              backgroundColor: Colors.red[300],
                                              child: const Icon(
                                                Icons.admin_panel_settings,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Admin: $adminName',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.red,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                  if (room.toMap().containsKey('description'))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2.0),
                                      child: Text(
                                        room.toMap()['description'],
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.red,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      'Members: ${room.approvedMembers.length}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BlockedUserScreen(
                                      roomName: room.name,
                                      spamResult: SpamResult(
                                        isSpam: true,
                                        confidence: 1.0,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
            // Normal rooms
            ...approvedRooms.map((room) {
              // ...existing code for normal rooms...
              String lastMessage = '';
              int unreadCount = 0;
              String? avatarUrl;
              if (room.toMap().containsKey('lastMessage')) {
                lastMessage = room.toMap()['lastMessage'] ?? '';
              }
              if (room.toMap().containsKey('unreadCount')) {
                unreadCount = room.toMap()['unreadCount'] ?? 0;
              }
              if (room.toMap().containsKey('photoUrl')) {
                avatarUrl = room.toMap()['photoUrl'];
              } else if (room.toMap().containsKey('imageUrl')) {
                avatarUrl = room.toMap()['imageUrl'];
              }
              final adminDisplayName =
                  room.toMap()['adminDisplayName'] ?? room.toMap()['adminName'];
              return FutureBuilder<String>(
                future: adminDisplayName != null
                    ? Future.value(adminDisplayName)
                    : fetchAdminDisplayName(room.adminUid),
                builder: (context, snapshot) {
                  final adminName = snapshot.data ?? room.adminUid;
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.green[400],
                        backgroundImage:
                            avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: (avatarUrl == null || avatarUrl.isEmpty)
                            ? Text(
                                room.name.isNotEmpty
                                    ? room.name[0].toUpperCase()
                                    : 'R',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              )
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              room.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          lastMessage.isNotEmpty
                              ? Text(
                                  lastMessage,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.blue[300],
                                      child: const Icon(
                                        Icons.admin_panel_settings,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Admin: $adminName',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.blue,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                          if (room.toMap().containsKey('description'))
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                room.toMap()['description'],
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              'Members: ${room.approvedMembers.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          if (room.toMap().containsKey('lastActivity'))
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                'Last active: ${room.toMap()['lastActivity']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (room.adminUid == user?.uid &&
                              room.pendingMembers.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.hourglass_top,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${room.pendingMembers.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RoomChatScreen(room: room),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // Try to refresh via provider if available
              try {
                final provider = Provider.of<ChatProvider>(
                  context,
                  listen: false,
                );
                await provider.refreshRooms();
                // Notify parent about unread count if callback provided
                if (widget.onUnreadCountChanged != null) {
                  widget.onUnreadCountChanged!(provider.unreadCount);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chats refreshed')),
                );
              } catch (e) {
                // Fallback: trigger rebuild
                setState(() {});
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
              }
            },
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          if (chatProvider.rooms.isEmpty) {
            return const Center(child: Text('No rooms found'));
          }
          return chatListBuilder(chatProvider.rooms);
        },
      ),
    );
  }
}
