import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tapzee/services/openstreetmap_service.dart';
import 'package:tapzee/services/user_location_service.dart';
import 'package:tapzee/widgets/user_marker_widget.dart';
import 'package:tapzee/screens/create_room_screen.dart';
import 'package:tapzee/models/room.dart';

class EnhancedMapWidget extends StatefulWidget {
  final LatLng? initialLocation;
  final List<LatLng>? markers;
  final Function(LatLng)? onTap;
  final double zoom;
  final bool showPOIs;
  final bool showSearch;

  const EnhancedMapWidget({
    Key? key,
    this.initialLocation,
    this.markers,
    this.onTap,
    this.zoom = 13.0,
    this.showPOIs = true,
    this.showSearch = true,
  }) : super(key: key);

  @override
  _EnhancedMapWidgetState createState() => _EnhancedMapWidgetState();
}

class _EnhancedMapWidgetState extends State<EnhancedMapWidget> {
  late MapController mapController;
  LatLng? currentLocation;
  bool isLoading = true;
  bool isRefreshingUsers = false;
  List<PointOfInterest> nearbyPOIs = [];
  List<PlaceResult> searchResults = [];
  List<AppUser> onlineUsers = [];
  TextEditingController searchController = TextEditingController();
  bool isSearching = false;
  bool showSearchResults = false;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    _getCurrentLocation();
    _subscribeToOnlineUsers();
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    // Immediately update location when widget initializes
    _updateCurrentUserLocation();

    // Set up periodic location updates every 30 seconds
    Stream.periodic(const Duration(seconds: 60)).listen((_) {
      if (mounted) {
        _updateCurrentUserLocation();
      }
    });
  }

  Future<void> _updateCurrentUserLocation() async {
    try {
      await UserLocationService.updateUserLocation();
    } catch (e) {
      print('Error updating user location: $e');
    }
  }

  void _subscribeToOnlineUsers() {
    // Listen to all online users stream (not just nearby)
    UserLocationService.getAllOnlineUsersStream().listen(
      (users) {
        print('Received ${users.length} online users');
        for (var user in users) {
          print(
            'User: ${user.displayName ?? user.email} at ${user.location.latitude}, ${user.location.longitude}',
          );
        }
        if (mounted) {
          setState(() {
            onlineUsers = users;
          });

          // Auto-adjust map to show all users
          _adjustMapToShowAllUsers(users);
        }
      },
      onError: (error) {
        print('Error listening to online users: $error');
      },
    );
  }

  // Auto-adjust map to show all users
  void _adjustMapToShowAllUsers(List<AppUser> users) {
    if (users.isEmpty || currentLocation == null) return;

    // Create a list of all locations (current user + online users)
    List<LatLng> allLocations = [currentLocation!];
    allLocations.addAll(users.map((user) => user.location));

    // Calculate bounds
    double minLat = allLocations
        .map((loc) => loc.latitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLat = allLocations
        .map((loc) => loc.latitude)
        .reduce((a, b) => a > b ? a : b);
    double minLng = allLocations
        .map((loc) => loc.longitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLng = allLocations
        .map((loc) => loc.longitude)
        .reduce((a, b) => a > b ? a : b);

    // Calculate center point
    double centerLat = (minLat + maxLat) / 2;
    double centerLng = (minLng + maxLng) / 2;
    LatLng center = LatLng(centerLat, centerLng);

    // Calculate appropriate zoom level
    double latDiff = maxLat - minLat;
    double lngDiff = maxLng - minLng;
    double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    double zoom;
    // More granular zoom for extremely close users
    if (maxDiff < 0.00001) {
      // <1m
      zoom = 22.0; // Ultra max zoom
    } else if (maxDiff < 0.00002) {
      // ~2m
      zoom = 21.0;
    } else if (maxDiff < 0.00005) {
      // ~5m
      zoom = 20.0;
    } else if (maxDiff < 0.0001) {
      // ~10m
      zoom = 19.0;
    } else if (maxDiff < 0.0005) {
      // ~50m
      zoom = 18.0;
    } else if (maxDiff < 0.001) {
      // ~100m
      zoom = 17.0;
    } else if (maxDiff < 0.01) {
      zoom = 15.0;
    } else if (maxDiff < 0.1) {
      zoom = 13.0;
    } else if (maxDiff < 1.0) {
      zoom = 10.0;
    } else {
      zoom = 8.0;
    }

    // Add some padding by reducing zoom slightly, except for max zoom
    if (zoom < 22.0) {
      zoom = zoom - 0.5;
    }
    if (zoom < 2.0) zoom = 2.0; // Minimum zoom
    if (zoom > 22.0) zoom = 22.0; // Maximum zoom

    // Move map to show all users
    try {
      mapController.move(center, zoom);
      print(
        'Adjusted map to center: $center, zoom: $zoom to show ${users.length} users',
      );
    } catch (e) {
      print('Error adjusting map: $e');
    }
  }

  // Refresh nearby users and current location
  Future<void> _refreshMap() async {
    setState(() {
      isRefreshingUsers = true;
    });

    try {
      // Update current user's location in Firestore
      await UserLocationService.updateUserLocation();

      // Get fresh list of all online users
      List<AppUser> users = await UserLocationService.getAllOnlineUsers();

      // Update current location
      await _getCurrentLocation();

      if (mounted) {
        setState(() {
          onlineUsers = users;
          isRefreshingUsers = false;
        });

        // Auto-adjust map to show all users
        _adjustMapToShowAllUsers(users);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.refresh, color: Colors.white),
                const SizedBox(width: 8),
                Text('Map refreshed! Found ${users.length} online users'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isRefreshingUsers = false;
        });

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Text('Failed to refresh: ${e.toString()}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EnhancedMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update map location if initialLocation changed
    if (widget.initialLocation != oldWidget.initialLocation &&
        widget.initialLocation != null) {
      _updateMapLocation(widget.initialLocation!);
    }
  }

  // Method to update map location programmatically
  void _updateMapLocation(LatLng newLocation) {
    if (mounted) {
      setState(() {
        currentLocation = newLocation;
      });
      // Animate to the new location
      mapController.move(newLocation, widget.zoom);
    }
  }

  // Fetch all available rooms that users can add others to
  Future<List<Room>> _fetchAllAvailableRooms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('rooms')
          .orderBy('createdAt', descending: true)
          .limit(20) // Limit to recent 20 rooms
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Add document ID to the data
        return Room.fromMap(data);
      }).toList();
    } catch (e) {
      print('Error fetching available rooms: $e');
      return [];
    }
  }

  // Add user to an existing room
  Future<void> _addUserToRoom(Room room, AppUser userToAdd) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isUserAdmin = currentUser?.uid == room.adminUid;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add User to Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add ${userToAdd.displayName ?? userToAdd.email} to:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    isUserAdmin ? Icons.admin_panel_settings : Icons.group,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        Text(
                          '${room.approvedMembers.length} members',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade600,
                          ),
                        ),
                        if (isUserAdmin)
                          Text(
                            'Your room',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isUserAdmin
                  ? 'The user will be added to your room immediately.'
                  : 'The user will be added as a pending member. The room admin will need to approve them.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add User'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Add the user to the room's pending members list
      await FirebaseFirestore.instance.collection('rooms').doc(room.id).update({
        'pendingMembers': FieldValue.arrayUnion([userToAdd.id]),
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.person_add, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${userToAdd.displayName ?? userToAdd.email} invited to "${room.name}"!',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add user to room: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Show user info when user marker is tapped
  void _showUserInfo(AppUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            UserMarkerWidget(
              photoURL: user.photoURL,
              displayName: user.displayName ?? user.email,
              isOnline: user.isOnline,
              size: 30.0,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user.displayName ?? user.email,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Email: ${user.email}'),
              const SizedBox(height: 8),
              Text('Status: ${user.isOnline ? 'Online' : 'Offline'}'),
              const SizedBox(height: 8),
              Text('Last seen: ${_formatDateTime(user.lastSeen)}'),
              const SizedBox(height: 8),
              Text(
                'Location: ${user.location.latitude.toStringAsFixed(4)}, ${user.location.longitude.toStringAsFixed(4)}',
              ),
              const SizedBox(height: 16),

              // Available rooms section
              FutureBuilder<List<Room>>(
                future: _fetchAllAvailableRooms(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Text(
                      'Error loading rooms: ${snapshot.error}',
                      style: TextStyle(color: Colors.red.shade600),
                    );
                  }

                  final rooms = snapshot.data ?? [];

                  if (rooms.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade600,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No rooms available yet. Create the first room to get started!',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add to available room:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: rooms.length,
                          itemBuilder: (context, index) {
                            final room = rooms[index];
                            final isUserAdmin =
                                FirebaseAuth.instance.currentUser?.uid ==
                                room.adminUid;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 15,
                                  backgroundColor: isUserAdmin
                                      ? Colors.blue.shade100
                                      : Colors.green.shade100,
                                  child: Icon(
                                    isUserAdmin
                                        ? Icons.admin_panel_settings
                                        : Icons.group,
                                    size: 16,
                                    color: isUserAdmin
                                        ? Colors.blue.shade700
                                        : Colors.green.shade700,
                                  ),
                                ),
                                title: Text(
                                  room.name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${room.approvedMembers.length} members',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    if (isUserAdmin)
                                      Text(
                                        'Your room',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.person_add, size: 18),
                                  onPressed: () {
                                    Navigator.of(
                                      context,
                                    ).pop(); // Close dialog first
                                    _addUserToRoom(room, user);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),

              // Create new room section
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_location,
                      color: Colors.blue.shade600,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Or create a new room to meet up with ${user.displayName ?? 'this user'}!',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop(); // Close the dialog first

              // Navigate to create room screen with pre-filled location
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CreateRoomScreen(
                    prefilledLocation: user.location,
                    suggestedTitle:
                        'Meet with ${user.displayName ?? user.email.split('@')[0]}',
                  ),
                ),
              );

              // If room was created successfully, show a confirmation
              if (result == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Room created near ${user.displayName ?? 'user'}!',
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add_location),
            label: const Text('Create Room'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        if (mounted) {
          setState(() {
            currentLocation = LatLng(position.latitude, position.longitude);
            isLoading = false;
          });

          // Move map to current location if no initial location provided
          if (widget.initialLocation == null) {
            mapController.move(currentLocation!, widget.zoom);
          }

          // Load nearby POIs
          if (widget.showPOIs) {
            _loadNearbyPOIs();
          }
        }
      } else {
        // Use default location
        if (mounted) {
          setState(() {
            currentLocation = LatLng(6.9271, 79.8612); // Default to Colombo
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error getting location: $e');
      if (mounted) {
        setState(() {
          currentLocation = LatLng(6.9271, 79.8612); // Default to Colombo
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loadNearbyPOIs() async {
    if (currentLocation == null) return;

    try {
      List<PointOfInterest> pois = await OpenStreetMapService.findNearbyPOIs(
        currentLocation!,
        2000, // 2km radius
        amenities: [
          'restaurant',
          'cafe',
          'hospital',
          'school',
          'bank',
          'fuel',
          'pharmacy',
        ],
      );

      if (mounted) {
        setState(() {
          nearbyPOIs = pois;
        });
      }
    } catch (e) {
      print('Error loading POIs: $e');
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
        showSearchResults = false;
      });
      return;
    }

    setState(() {
      isSearching = true;
    });

    try {
      List<PlaceResult> results = await OpenStreetMapService.searchPlaces(
        query,
        center: currentLocation,
        radius: 0.1, // Search within reasonable distance
        limit: 10,
      );

      if (mounted) {
        setState(() {
          searchResults = results;
          showSearchResults = true;
          isSearching = false;
        });
      }
    } catch (e) {
      print('Error searching places: $e');
      if (mounted) {
        setState(() {
          isSearching = false;
          showSearchResults = false;
        });
      }
    }
  }

  void _moveToLocation(LatLng location, {double? zoom}) {
    mapController.move(location, zoom ?? 16.0);
    setState(() {
      showSearchResults = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading map...'),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            center:
                widget.initialLocation ??
                currentLocation ??
                LatLng(6.9271, 79.8612),
            zoom: widget.zoom,
            onTap: (tapPosition, point) {
              setState(() {
                showSearchResults = false;
              });
              if (widget.onTap != null) {
                widget.onTap!(point);
              }
            },
            interactiveFlags: InteractiveFlag.all,
          ),
          children: [
            // Map tiles
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.tapzee',
              maxZoom: 19,
              backgroundColor: Colors.grey[200],
            ),

            // Current location marker (current user)
            if (currentLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: currentLocation!,
                    width: 60,
                    height: 60,
                    child: CurrentUserMarkerWidget(
                      photoURL: FirebaseAuth.instance.currentUser?.photoURL,
                      displayName:
                          FirebaseAuth.instance.currentUser?.displayName ??
                          FirebaseAuth.instance.currentUser?.email ??
                          'Me',
                      size: 45.0,
                    ),
                  ),
                ],
              ),

            // Nearby users markers
            if (onlineUsers.isNotEmpty) ...[
              MarkerLayer(
                markers: onlineUsers.map((user) {
                  print(
                    'Creating marker for user: ${user.displayName ?? user.email}',
                  );
                  return Marker(
                    point: user.location,
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () {
                        _showUserInfo(user);
                      },
                      child: UserMarkerWidget(
                        photoURL: user.photoURL,
                        displayName: user.displayName ?? user.email,
                        isOnline: user.isOnline,
                        size: 40.0,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Room markers
            if (widget.markers != null && widget.markers!.isNotEmpty)
              MarkerLayer(
                markers: widget.markers!
                    .map(
                      (point) => Marker(
                        point: point,
                        width: 50,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),

            // POI markers
            if (widget.showPOIs && nearbyPOIs.isNotEmpty)
              MarkerLayer(
                markers: nearbyPOIs
                    .map(
                      (poi) => Marker(
                        point: poi.location,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _showPOIDetails(poi),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _getPOIColor(poi.amenity),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Icon(
                              poi.icon,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),

        // Nearby users count indicator
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${onlineUsers.length} online users',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isRefreshingUsers) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Search bar
        if (widget.showSearch)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search places...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setState(() {
                                  searchResults = [];
                                  showSearchResults = false;
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      _searchPlaces(value);
                    },
                  ),
                ),

                // Search results
                if (showSearchResults && searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        PlaceResult place = searchResults[index];
                        return ListTile(
                          leading: Icon(Icons.place, color: Colors.blue),
                          title: Text(place.shortName),
                          subtitle: Text(
                            place.fullAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _moveToLocation(place.location),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

        // Map controls
        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            children: [
              // Refresh nearby users and map
              Tooltip(
                message: 'Refresh online users (${onlineUsers.length} found)',
                child: FloatingActionButton(
                  mini: true,
                  heroTag: "refresh_users",
                  onPressed: isRefreshingUsers ? null : _refreshMap,
                  backgroundColor: Colors.white,
                  child: isRefreshingUsers
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.orange,
                            ),
                          ),
                        )
                      : Icon(Icons.people, color: Colors.orange),
                ),
              ),
              const SizedBox(height: 8),

              // Fit all users in view
              if (onlineUsers.isNotEmpty)
                FloatingActionButton(
                  mini: true,
                  heroTag: "fit_users",
                  onPressed: () => _adjustMapToShowAllUsers(onlineUsers),
                  backgroundColor: Colors.white,
                  child: Icon(Icons.zoom_out_map, color: Colors.orange),
                  tooltip: 'Fit all ${onlineUsers.length} users in view',
                ),
              if (onlineUsers.isNotEmpty) const SizedBox(height: 8),

              // Zoom to current location
              FloatingActionButton(
                mini: true,
                heroTag: "location",
                onPressed: currentLocation != null
                    ? () => _moveToLocation(currentLocation!, zoom: 16.0)
                    : null,
                backgroundColor: Colors.white,
                child: Icon(Icons.my_location, color: Colors.blue),
              ),
              const SizedBox(height: 8),

              // Refresh POIs
              if (widget.showPOIs)
                FloatingActionButton(
                  mini: true,
                  heroTag: "refresh",
                  onPressed: _loadNearbyPOIs,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.refresh, color: Colors.green),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getPOIColor(String amenity) {
    switch (amenity) {
      case 'restaurant':
        return Colors.orange;
      case 'cafe':
        return Colors.brown;
      case 'hospital':
        return Colors.red;
      case 'school':
        return Colors.blue;
      case 'bank':
        return Colors.green;
      case 'fuel':
        return Colors.purple;
      case 'pharmacy':
        return Colors.lightBlue;
      default:
        return Colors.grey;
    }
  }

  void _showPOIDetails(PointOfInterest poi) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(poi.icon, color: _getPOIColor(poi.amenity)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    poi.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              poi.category,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            if (currentLocation != null) ...[
              const SizedBox(height: 8),
              Text(
                'Distance: ${OpenStreetMapService.formatDistance(OpenStreetMapService.calculateDistance(currentLocation!, poi.location))}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _moveToLocation(poi.location);
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Go Here'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
