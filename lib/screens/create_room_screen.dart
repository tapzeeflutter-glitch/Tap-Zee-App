import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/services/location_testing_service.dart';
import 'package:tapzee/services/user_location_service.dart';

class CreateRoomScreen extends StatefulWidget {
  final LatLng? prefilledLocation;
  final String? suggestedTitle;

  const CreateRoomScreen({
    super.key,
    this.prefilledLocation,
    this.suggestedTitle,
  });

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _roomNameController = TextEditingController();
  final _roomDescriptionController = TextEditingController();
  final _roomRadiusController = TextEditingController(text: '100');

  Stream<List<AppUser>>? _nearbyUsersStream;
  final List<Map<String, dynamic>> _selectedMembers = [];

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String? _error;
  bool _isLoading = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();

    if (widget.suggestedTitle != null) {
      _roomNameController.text = widget.suggestedTitle!;
    }

    _getCurrentLocation();
    _nearbyUsersStream = UserLocationService.getNearbyUsersStream(
      radiusInMeters: 5000,
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _roomDescriptionController.dispose();
    _roomRadiusController.dispose();
    super.dispose();
  }

  void _addMemberFromAppUser(AppUser user) {
    if (_selectedMembers.any((m) => m['uid'] == user.id)) return;
    setState(() {
      _selectedMembers.add({
        'uid': user.id,
        'displayName': user.displayName ?? user.email,
        'photoURL': user.photoURL,
      });
    });
  }

  void _removeSelectedMember(String uid) {
    setState(() {
      _selectedMembers.removeWhere((m) => m['uid'] == uid);
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (widget.prefilledLocation != null) {
        _currentPosition = Position(
          latitude: widget.prefilledLocation!.latitude,
          longitude: widget.prefilledLocation!.longitude,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
      } else {
        LatLng? testLocation = LocationTestingService.getCurrentTestLocation();
        if (testLocation != null) {
          _currentPosition = Position(
            latitude: testLocation.latitude,
            longitude: testLocation.longitude,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
          );
        } else {
          _currentPosition = await Geolocator.getCurrentPosition();
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to get current location: $e';
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _createRoom() async {
    if (!_formKey.currentState!.validate()) return;

    if (_currentPosition == null) {
      setState(() {
        _error = 'Cannot create room without current location.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'No user logged in.';
        _isLoading = false;
      });
      return;
    }

    try {
      final roomId = _firestore.collection('rooms').doc().id;
      final newRoom = Room(
        id: roomId,
        name: _roomNameController.text.trim(),
        description: _roomDescriptionController.text.trim(),
        adminUid: user.uid,
        location: GeoPoint(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        ),
        radius: double.tryParse(_roomRadiusController.text.trim()) ?? 100.0,
        createdAt: Timestamp.now(),
        approvedMembers: [user.uid],
        pendingMembers: _selectedMembers
            .map((m) => m['uid'] as String)
            .where((uid) => uid != user.uid)
            .toSet()
            .toList(),
        rules: [],
      );

      await _firestore.collection('rooms').doc(roomId).set(newRoom.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? 'Firebase error occurred';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'An unexpected error occurred: $e';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Room')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Add members',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedMembers
                          .map(
                            (m) => Chip(
                              avatar: m['photoURL'] != null
                                  ? CircleAvatar(
                                      backgroundImage: NetworkImage(
                                        m['photoURL'],
                                      ),
                                    )
                                  : null,
                              label: Text(m['displayName'] ?? 'User'),
                              onDeleted: () => _removeSelectedMember(m['uid']),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),
                    StreamBuilder<List<AppUser>>(
                      stream: _nearbyUsersStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final users = snapshot.data ?? [];
                        if (users.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('No nearby online users found.'),
                          );
                        }

                        return Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final alreadySelected = _selectedMembers.any(
                                (m) => m['uid'] == user.id,
                              );
                              return ListTile(
                                leading: user.photoURL != null
                                    ? CircleAvatar(
                                        backgroundImage: NetworkImage(
                                          user.photoURL!,
                                        ),
                                      )
                                    : const CircleAvatar(
                                        child: Icon(Icons.person),
                                      ),
                                title: Text(user.displayName ?? user.email),
                                subtitle: Text(user.email),
                                trailing: alreadySelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.green,
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.person_add),
                                        onPressed: () =>
                                            _addMemberFromAppUser(user),
                                      ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (widget.prefilledLocation != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.group_add, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Creating a room at the location of another user. They\'ll be able to see and join this room!',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    TextFormField(
                      controller: _roomNameController,
                      decoration: const InputDecoration(labelText: 'Room Name'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a room name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _roomDescriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 24),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        margin: const EdgeInsets.only(bottom: 16.0),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _createRoom,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade500,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create Room',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
