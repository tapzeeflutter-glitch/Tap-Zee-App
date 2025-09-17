import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:tapzee/widgets/enhanced_map_widget.dart';
import 'package:tapzee/screens/create_room_screen.dart';
import 'package:tapzee/screens/my_rooms_tab.dart';
import 'package:tapzee/screens/chats_tab.dart';
import 'package:tapzee/screens/user_profile_page.dart';
import 'package:tapzee/services/location_testing_service.dart';
import 'package:tapzee/services/user_location_service.dart';
import 'package:tapzee/models/room.dart';

import '../widgets/app_logo.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

Position? _currentPosition; // Current position of the user
String _roomSearchQuery = ''; // Search query for filtering rooms
bool _shareLocation = true; // Toggle for sharing location
// Removed MapType and nearbyUsers from top-level (should be in State class)

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  int _unreadChatsCount = 0;
  final _firestore = FirebaseFirestore.instance;
  Position? _currentPosition;
  String? _locationError;
  bool _isLoadingLocation = false;
  List<LatLng> _roomMarkers = [];
  final GlobalKey _mapKey = GlobalKey();
  StreamSubscription<QuerySnapshot>? _pendingRoomsSub;
  int _pendingAppealsCount = 0; // Track pending appeals count
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _appealsSub;
  // ...existing code...
  // Add nearby users and map type to State class
  List<AppUser> _nearbyUsers = [];
  // If you want to support map type switching, define your own enum or use a bool for now
  // Example:SWS
  // bool _isSatelliteMap = false;
  // Implement _fetchNearbyUsers method
  Future<void> _fetchNearbyUsers() async {
    if (_currentPosition == null) return;
    try {
      final querySnapshot = await _firestore.collection('users').get();
      List<AppUser> users = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final user = AppUser.fromMap(data, doc.id);
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          user.location.latitude,
          user.location.longitude,
        );
        if (distance <= 1000 &&
            user.id != FirebaseAuth.instance.currentUser?.uid) {
          users.add(user);
        }
      }
      setState(() {
        _nearbyUsers = users;
      });
    } catch (e) {
      print('Error fetching nearby users: $e');
    }
  }

  List<DocumentSnapshot> _pendingRooms = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();
    // Start real-time listener for pending room invitations
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _pendingRoomsSub = FirebaseFirestore.instance
          .collection('rooms')
          .where('pendingMembers', arrayContains: user.uid)
          .snapshots()
          .listen(
            (snapshot) {
              if (mounted) {
                setState(() {
                  _pendingRooms = snapshot.docs;
                });
                _listenPendingAppealsCount(user.uid);
              }
            },
            onError: (e) {
              print('Pending rooms listener error: $e');
            },
          );
    } else {
      _fetchPendingRooms(); // fallback for unauthenticated state
    }
  }

  void _listenPendingAppealsCount(String adminUid) async {
    _appealsSub?.cancel();
    final roomsStream = FirebaseFirestore.instance
        .collection('rooms')
        .where('adminUid', isEqualTo: adminUid)
        .snapshots();
    _appealsSub = roomsStream.listen((roomsSnapshot) async {
      int appealsCount = 0;
      List<Future<int>> appealCounts = [];
      for (var roomDoc in roomsSnapshot.docs) {
        appealCounts.add(
          roomDoc.reference
              .collection('appeals')
              .snapshots()
              .first
              .then((snap) => snap.size),
        );
      }
      final counts = await Future.wait(appealCounts);
      appealsCount = counts.fold(0, (a, b) => a + b);
      if (mounted) {
        setState(() {
          _pendingAppealsCount = appealsCount;
        });
      }
    });
  }

  Future<void> _fetchPendingAppealsCount(String adminUid) async {
    int appealsCount = 0;
    final roomsSnapshot = await FirebaseFirestore.instance
        .collection('rooms')
        .where('adminUid', isEqualTo: adminUid)
        .get();
    for (var roomDoc in roomsSnapshot.docs) {
      final appealsSnapshot = await roomDoc.reference
          .collection('appeals')
          .get();
      appealsCount += appealsSnapshot.size;
    }
    if (mounted) {
      setState(() {
        _pendingAppealsCount = appealsCount;
      });
    }
  }

  // Fetch rooms where current user is in pendingMembers
  Future<void> _fetchPendingRooms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final query = await FirebaseFirestore.instance
        .collection('rooms')
        .where('pendingMembers', arrayContains: user.uid)
        .get();
    setState(() {
      _pendingRooms = query.docs;
    });
  }

  Future<void> _refreshPendingRooms() async {
    await _fetchPendingRooms();
  }

  Future<void> _initializeApp() async {
    // Start tracking user location for other users to see
    await UserLocationService.startLocationTracking();

    // Set up location change callback for map updates
    LocationTestingService.setLocationChangeCallback(_onLocationChanged);

    // Determine initial position and start listening for nearby users
    await _determinePosition();
  }

  @override
  void dispose() {
    // Clean up the callback and stop location tracking
    LocationTestingService.setLocationChangeCallback(null);
    UserLocationService.stopLocationTracking();
    // Cancel pending rooms listener
    _pendingRoomsSub?.cancel();
    _appealsSub?.cancel();
    super.dispose();
  }

  void _onLocationChanged(LatLng? newLocation) async {
    if (mounted) {
      // If we have a test location, update the position immediately
      if (newLocation != null) {
        setState(() {
          _currentPosition = Position(
            latitude: newLocation.latitude,
            longitude: newLocation.longitude,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
          );
        });

        // Update location in Firebase immediately when test location changes
        await UserLocationService.updateUserLocation();

        // Fetch nearby rooms for the new location
        _fetchNearbyRooms();
      } else {
        // Reset to GPS location
        _determinePosition();
      }
    }
  }

  // Refresh home tab data
  Future<void> _refreshHomeTab() async {
    // Update user location in Firestore
    await UserLocationService.updateUserLocation();

    // Refresh current position and nearby rooms
    await _determinePosition();
    await _fetchNearbyRooms();
  }

  Future<void> _determinePosition() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      // Check if we're using custom location for testing
      LatLng? testLocation = LocationTestingService.getCurrentTestLocation();
      if (testLocation != null) {
        // Use custom test location
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

        setState(() {
          _isLoadingLocation = false;
        });

        await _fetchNearbyRooms();
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError =
              'Location services are disabled. Please enable location in your browser or use custom location for testing.';
          Future<void> _fetchNearbyUsers() async {
            // Fetch users near the current position
            if (_currentPosition == null) return;
            try {
              final querySnapshot = await _firestore.collection('users').get();
              List<AppUser> users = [];
              for (var doc in querySnapshot.docs) {
                final data = doc.data();
                final user = AppUser.fromMap(data, doc.id);
                final distance = Geolocator.distanceBetween(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  user.location.latitude,
                  user.location.longitude,
                );
                if (distance <= 1000 &&
                    user.id != FirebaseAuth.instance.currentUser?.uid) {
                  users.add(user);
                }
              }
              setState(() {
                _nearbyUsers = users;
              });
            } catch (e) {
              print('Error fetching nearby users: $e');
            }
          }

          _isLoadingLocation = false;
        });
        return;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();

      // If permissions are denied, try to request them
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError =
                'Location permissions are denied. Please allow location access in your browser or use custom location for testing.';
            _isLoadingLocation = false;
          });
          return;
        }
      }

      // If permissions are permanently denied, show helpful message
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError =
              'Location permissions are permanently denied. Please enable location in your browser settings or use custom location for testing.';
          _isLoadingLocation = false;
        });
        return;
      }

      // Get current position from GPS
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      setState(() {
        _isLoadingLocation = false;
      });

      // Update user location in Firestore for other users to see
      await UserLocationService.updateUserLocation();
      await _fetchNearbyRooms();
    } catch (e) {
      setState(() {
        _locationError =
            'Failed to get current location: ${e.toString()}. This is common in web browsers. Please use custom location for testing or allow location access when prompted.';
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _fetchNearbyRooms() async {
    if (_currentPosition == null) return;

    try {
      List<LatLng> markers = [];

      // Fetch rooms from Firestore
      final querySnapshot = await _firestore.collection('rooms').get();

      for (var doc in querySnapshot.docs) {
        try {
          final roomData = doc.data();
          final room = Room.fromMap(roomData);

          final distance = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            room.location.latitude,
            room.location.longitude,
          );

          // Display rooms within the specified radius
          if (distance <= room.radius) {
            markers.add(
              LatLng(room.location.latitude, room.location.longitude),
            );
          }
        } catch (e) {
          print('Error processing room document ${doc.id}: $e');
          // Continue processing other rooms even if one fails
        }
      }

      if (mounted) {
        setState(() {
          _roomMarkers = markers;
        });
      }
    } catch (e) {
      print('Error fetching rooms: $e');
    }
  }

  void _showLocationTestingDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: LocationTestingWidget(
            onLocationChanged: (location) {
              // This callback is now handled by the service callback
              // but we can add additional logic here if needed
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _refreshHomeTab,
      child: _isLoadingLocation
          ? const Center(child: CircularProgressIndicator())
          : _locationError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_off,
                        size: 64,
                        color: Colors.orange.shade600,
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Text(
                                'Location Access Issue',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Colors.orange.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _locationError!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.lightbulb,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Quick Solution: Use Custom Location',
                                      style: TextStyle(
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Perfect for testing the app with different locations!',
                                      style: TextStyle(
                                        color: Colors.blue.shade600,
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _showLocationTestingDialog,
                                      icon: const Icon(Icons.location_on),
                                      label: const Text('Use Custom Location'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _determinePosition,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Try Again'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: EnhancedMapWidget(
                    key: _mapKey,
                    initialLocation: _currentPosition != null
                        ? LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          )
                        : null,
                    markers: _roomMarkers,
                    zoom: 15.0,
                    showPOIs: true,
                    showSearch: false,
                    onTap: (point) {
                      print(
                        'Map tapped at: ${point.latitude}, ${point.longitude}',
                      );
                    },
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_currentPosition != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: LocationTestingService.useCustomLocation
                                  ? Colors.orange.shade50
                                  : Colors.green.shade50,
                              border: Border.all(
                                color: LocationTestingService.useCustomLocation
                                    ? Colors.orange.shade200
                                    : Colors.green.shade200,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      LocationTestingService.useCustomLocation
                                          ? Icons.location_on
                                          : Icons.gps_fixed,
                                      color:
                                          LocationTestingService
                                              .useCustomLocation
                                          ? Colors.orange.shade700
                                          : Colors.green.shade700,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        LocationTestingService.getLocationDisplayName(),
                                        style: TextStyle(
                                          color:
                                              LocationTestingService
                                                  .useCustomLocation
                                              ? Colors.orange.shade700
                                              : Colors.green.shade700,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (LocationTestingService
                                    .useCustomLocation) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '💡 Perfect for multi-user testing with nearby phones',
                                    style: TextStyle(
                                      color: Colors.orange.shade600,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () async {
                            // Navigate to create room screen
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const CreateRoomScreen(),
                              ),
                            );
                            // Refresh the data when returning from create room screen
                            if (mounted) {
                              await _fetchNearbyRooms();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: const Text('Create Room'),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMyRoomsTab() {
    return const MyRoomsTab();
  }

  Widget _buildChatsTab() {
    return ChatsTab(
      onUnreadCountChanged: (count) {
        if (_unreadChatsCount != count) {
          setState(() {
            _unreadChatsCount = count;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: AppLogoWithText(
          appName: 'Tap Zee',
          logoSize: 32,
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Pending rooms and appeals notification icon with refresh
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                tooltip: 'Room Invitations & Appeals',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Pending Room'),
                              Text('Invitations'),
                              Text('Appeals'),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.blue),
                            tooltip: 'Refresh',
                            onPressed: () {
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: Column(
                          children: [
                            // Pending invitations
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('rooms')
                                  .where(
                                    'pendingMembers',
                                    arrayContains: user?.uid,
                                  )
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return Center(
                                    child: Text('Error: ${snapshot.error}'),
                                  );
                                }
                                final docs = snapshot.data?.docs ?? [];
                                if (docs.isEmpty) {
                                  return const Text('No pending invitations.');
                                }
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ...docs.map((doc) {
                                      final data =
                                          doc.data() as Map<String, dynamic>? ??
                                          {};
                                      final roomName = data['name'] ?? 'Room';
                                      final roomDesc =
                                          data['description'] ?? '';
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: ListTile(
                                          title: Text(
                                            roomName,
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          subtitle: Text(
                                            roomDesc,
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 13,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextButton(
                                                onPressed: () async {
                                                  final uid = user?.uid;
                                                  if (uid == null) return;
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection('rooms')
                                                      .doc(doc.id)
                                                      .update({
                                                        'pendingMembers':
                                                            FieldValue.arrayRemove(
                                                              [uid],
                                                            ),
                                                        'approvedMembers':
                                                            FieldValue.arrayUnion(
                                                              [uid],
                                                            ),
                                                      });
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'You joined $roomName!',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: const Text('Accept'),
                                              ),
                                              TextButton(
                                                onPressed: () async {
                                                  final uid = user?.uid;
                                                  if (uid == null) return;
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection('rooms')
                                                      .doc(doc.id)
                                                      .update({
                                                        'pendingMembers':
                                                            FieldValue.arrayRemove(
                                                              [uid],
                                                            ),
                                                      });
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Request declined.',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: const Text('Decline'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            // Appeals for admin
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('rooms')
                                  .where('adminUid', isEqualTo: user?.uid)
                                  .snapshots(),
                              builder: (context, roomSnapshot) {
                                if (roomSnapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (roomSnapshot.hasError) {
                                  return Center(
                                    child: Text('Error: ${roomSnapshot.error}'),
                                  );
                                }
                                final adminRooms =
                                    roomSnapshot.data?.docs ?? [];
                                if (adminRooms.isEmpty) {
                                  return const Text('No rooms to manage.');
                                }
                                return Column(
                                  children: [
                                    ...adminRooms.map((roomDoc) {
                                      return StreamBuilder<QuerySnapshot>(
                                        stream: roomDoc.reference
                                            .collection('appeals')
                                            .snapshots(),
                                        builder: (context, appealsSnapshot) {
                                          if (appealsSnapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return const SizedBox();
                                          }
                                          final appeals =
                                              appealsSnapshot.data?.docs ?? [];
                                          if (appeals.isEmpty) {
                                            return const SizedBox();
                                          }
                                          return Container(
                                            constraints: const BoxConstraints(
                                              maxHeight: 600,
                                              minWidth: 900,
                                            ),
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.vertical,
                                              child: Column(
                                                children: [
                                                  ...appeals.map((appealDoc) {
                                                    final appeal =
                                                        appealDoc.data()
                                                            as Map<
                                                              String,
                                                              dynamic
                                                            >? ??
                                                        {};
                                                    final userName =
                                                        appeal['userName'] ??
                                                        '';
                                                    final userId =
                                                        appeal['userId'] ?? '';
                                                    final reason =
                                                        appeal['reason'] ?? '';
                                                    return Card(
                                                      color:
                                                          Colors.orange.shade50,
                                                      margin:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 4,
                                                          ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          SizedBox(
                                                            height: 8,
                                                            width: 500,
                                                          ),
                                                          Text(
                                                            'Appeal from $userName',
                                                            textAlign: TextAlign
                                                                .center,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 15,
                                                                ),
                                                          ),
                                                          Text(
                                                            reason,
                                                            textAlign: TextAlign
                                                                .center,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .orange,
                                                                  fontSize: 13,
                                                                  fontStyle:
                                                                      FontStyle
                                                                          .italic,
                                                                ),
                                                          ),
                                                          SizedBox(height: 8),
                                                          Wrap(
                                                            spacing: 12,
                                                            children: [
                                                              Container(
                                                                width: 220,
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      vertical:
                                                                          8,
                                                                      horizontal:
                                                                          8,
                                                                    ),
                                                                child: ElevatedButton.icon(
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor:
                                                                        Colors
                                                                            .green
                                                                            .shade600,
                                                                    foregroundColor:
                                                                        Colors
                                                                            .white,
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          24,
                                                                      vertical:
                                                                          12,
                                                                    ),
                                                                    textStyle: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ),
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .lock_open,
                                                                    size: 20,
                                                                  ),
                                                                  label: const Text(
                                                                    'Unblock',
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                  onPressed: () async {
                                                                    await roomDoc.reference.update({
                                                                      'blockedMembers':
                                                                          FieldValue.arrayRemove([
                                                                            userId,
                                                                          ]),
                                                                      'approvedMembers':
                                                                          FieldValue.arrayUnion([
                                                                            userId,
                                                                          ]),
                                                                    });
                                                                    await appealDoc
                                                                        .reference
                                                                        .delete();
                                                                  },
                                                                ),
                                                              ),
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      vertical:
                                                                          8,
                                                                      horizontal:
                                                                          8,
                                                                    ),
                                                                child: TextButton(
                                                                  style: TextButton.styleFrom(
                                                                    backgroundColor:
                                                                        Colors
                                                                            .grey
                                                                            .shade300,
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          16,
                                                                      vertical:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                  onPressed: () async {
                                                                    await appealDoc
                                                                        .reference
                                                                        .delete();
                                                                    ScaffoldMessenger.of(
                                                                      context,
                                                                    ).showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text(
                                                                              'Appeal declined.',
                                                                            ),
                                                                      ),
                                                                    );
                                                                  },
                                                                  child:
                                                                      const Text(
                                                                        'Decline',
                                                                      ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    }).toList(),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (_pendingRooms.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${_pendingRooms.length + _pendingAppealsCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const UserProfilePage(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue.shade100,
                backgroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: user?.photoURL == null
                    ? Text(
                        user?.displayName?.isNotEmpty == true
                            ? user!.displayName![0].toUpperCase()
                            : user?.email?.isNotEmpty == true
                            ? user!.email![0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [_buildHomeTab(), _buildMyRoomsTab(), _buildChatsTab()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.meeting_room),
            label: 'My Rooms',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.chat),
                if (_unreadChatsCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$_unreadChatsCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Chats',
          ),
        ],
      ),
      // FloatingActionButton for location testing removed. Now in user profile page.
    );
  }

  Future<void> _declineJoinRoom(String roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Add user to declinedRequests field for admin notification
    await FirebaseFirestore.instance.collection('rooms').doc(roomId).update({
      'pendingMembers': FieldValue.arrayRemove([user.uid]),
      'declinedRequests': FieldValue.arrayUnion([user.uid]),
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Join request declined.')));
  }
}
