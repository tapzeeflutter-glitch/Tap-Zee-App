import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tapzee/services/location_testing_service.dart';

class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? photoURL;
  final LatLng location;
  final DateTime lastSeen;
  final bool isOnline;

  AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoURL,
    required this.location,
    required this.lastSeen,
    this.isOnline = true,
  });

  factory AppUser.fromMap(Map<String, dynamic> data, String id) {
    return AppUser(
      id: id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      photoURL: data['photoURL'],
      location: LatLng(
        data['location']['latitude'] ?? 0.0,
        data['location']['longitude'] ?? 0.0,
      ),
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: data['isOnline'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'location': {
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
      'lastSeen': Timestamp.fromDate(lastSeen),
      'isOnline': isOnline,
    };
  }
}

class UserLocationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Update current user's location
  static Future<void> updateUserLocation() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      LatLng? location;

      // Check if using custom location for testing
      LatLng? testLocation = LocationTestingService.getCurrentTestLocation();
      if (testLocation != null) {
        location = testLocation;
        print(
          'Using custom test location: ${location.latitude}, ${location.longitude}',
        );
      } else {
        // Get real GPS location with better error handling for web
        try {
          // Check permissions first
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }

          if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) {
            print('Location permissions denied. Using fallback location.');
            location = LatLng(6.9271, 79.8612); // Colombo as fallback
          } else {
            // Try to get location with shorter timeout and lower accuracy for web
            try {
              Position position = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy
                      .medium, // Reduced accuracy for faster response
                  timeLimit: Duration(seconds: 8), // Shorter timeout
                ),
              );
              location = LatLng(position.latitude, position.longitude);
              print(
                'Got GPS location: ${location.latitude}, ${location.longitude}',
              );
            } catch (timeoutError) {
              print('GPS timeout, trying last known location...');
              // Try to get last known position
              Position? lastPosition = await Geolocator.getLastKnownPosition();
              if (lastPosition != null) {
                location = LatLng(
                  lastPosition.latitude,
                  lastPosition.longitude,
                );
                print(
                  'Using last known location: ${location.latitude}, ${location.longitude}',
                );
              } else {
                print('No last known location, using fallback.');
                location = LatLng(6.9271, 79.8612); // Colombo as fallback
              }
            }
          }
        } catch (e) {
          print('Error getting GPS location: $e');
          location = LatLng(6.9271, 79.8612); // Colombo as fallback
        }
      }

      // Update user document in Firestore
      await _firestore.collection('active_users').doc(user.uid).set({
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        'lastSeen': Timestamp.now(),
        'isOnline': true,
      }, SetOptions(merge: true));

      print(
        'Updated user location in Firestore: ${location.latitude}, ${location.longitude}',
      );
    } catch (e) {
      print('Error updating user location: $e');
    }
  }

  // Get all online users (not just nearby)
  static Future<List<AppUser>> getAllOnlineUsers() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      // Get all active users (simplified query - only filter by isOnline)
      QuerySnapshot snapshot = await _firestore
          .collection('active_users')
          .where('isOnline', isEqualTo: true)
          .get();

      List<AppUser> onlineUsers = [];

      for (QueryDocumentSnapshot doc in snapshot.docs) {
        // Skip current user
        if (doc.id == user.uid) continue;

        try {
          AppUser appUser = AppUser.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          );

          // Filter out users who haven't been seen in the last 15 minutes
          if (appUser.lastSeen.isAfter(
            DateTime.now().subtract(const Duration(minutes: 15)),
          )) {
            onlineUsers.add(appUser);
          }
        } catch (e) {
          print('Error processing user ${doc.id}: $e');
        }
      }

      return onlineUsers;
    } catch (e) {
      print('Error getting online users: $e');
      return [];
    }
  }

  // Listen to all online users in real-time
  static Stream<List<AppUser>> getAllOnlineUsersStream() {
    final user = _auth.currentUser;
    if (user == null) {
      print('No authenticated user for stream');
      return Stream.value([]);
    }

    print('Starting online users stream for user: ${user.email}');

    // Simplified query - only filter by isOnline
    return _firestore
        .collection('active_users')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          print(
            'Received ${snapshot.docs.length} total documents from Firestore',
          );
          List<AppUser> onlineUsers = [];

          for (QueryDocumentSnapshot doc in snapshot.docs) {
            print('Processing document: ${doc.id}');

            // Skip current user
            if (doc.id == user.uid) {
              print('Skipping current user: ${doc.id}');
              continue;
            }

            try {
              final data = doc.data() as Map<String, dynamic>;
              print('Document data: $data');

              AppUser appUser = AppUser.fromMap(data, doc.id);
              print(
                'Created AppUser: ${appUser.displayName ?? appUser.email} at ${appUser.location.latitude}, ${appUser.location.longitude}',
              );

              // Filter out users who haven't been seen in the last 15 minutes
              if (appUser.lastSeen.isAfter(
                DateTime.now().subtract(const Duration(minutes: 15)),
              )) {
                onlineUsers.add(appUser);
                print(
                  'Added user to online list: ${appUser.displayName ?? appUser.email}',
                );
              } else {
                print(
                  'User ${appUser.displayName ?? appUser.email} was last seen too long ago: ${appUser.lastSeen}',
                );
              }
            } catch (e) {
              print('Error processing user ${doc.id}: $e');
            }
          }

          print('Returning ${onlineUsers.length} online users');
          return onlineUsers;
        });
  }

  // Get nearby users within a certain radius (in meters)
  static Future<List<AppUser>> getNearbyUsers({
    double radiusInMeters = 5000,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      // Get current user's location
      LatLng? currentLocation;
      LatLng? testLocation = LocationTestingService.getCurrentTestLocation();
      if (testLocation != null) {
        currentLocation = testLocation;
      } else {
        Position position = await Geolocator.getCurrentPosition();
        currentLocation = LatLng(position.latitude, position.longitude);
      }

      // Get all active users (simplified query)
      QuerySnapshot snapshot = await _firestore
          .collection('active_users')
          .where('isOnline', isEqualTo: true)
          .get();

      List<AppUser> nearbyUsers = [];

      for (QueryDocumentSnapshot doc in snapshot.docs) {
        // Skip current user
        if (doc.id == user.uid) continue;

        try {
          AppUser appUser = AppUser.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          );

          // Filter by time (last 15 minutes)
          if (appUser.lastSeen.isBefore(
            DateTime.now().subtract(const Duration(minutes: 15)),
          )) {
            continue;
          }

          // Calculate distance
          double distance = Geolocator.distanceBetween(
            currentLocation.latitude,
            currentLocation.longitude,
            appUser.location.latitude,
            appUser.location.longitude,
          );

          // Add user if within radius
          if (distance <= radiusInMeters) {
            nearbyUsers.add(appUser);
          }
        } catch (e) {
          print('Error processing user ${doc.id}: $e');
        }
      }

      return nearbyUsers;
    } catch (e) {
      print('Error getting nearby users: $e');
      return [];
    }
  }

  // Mark user as offline
  static Future<void> markUserOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('active_users').doc(user.uid).update({
        'isOnline': false,
        'lastSeen': Timestamp.now(),
      });
    } catch (e) {
      print('Error marking user offline: $e');
    }
  }

  // Listen to nearby users in real-time
  static Stream<List<AppUser>> getNearbyUsersStream({
    double radiusInMeters = 5000,
  }) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('active_users')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .asyncMap((snapshot) async {
          // Get current user's location
          LatLng? currentLocation;
          LatLng? testLocation =
              LocationTestingService.getCurrentTestLocation();
          if (testLocation != null) {
            currentLocation = testLocation;
          } else {
            try {
              Position position = await Geolocator.getCurrentPosition();
              currentLocation = LatLng(position.latitude, position.longitude);
            } catch (e) {
              print('Error getting current location: $e');
              return <AppUser>[];
            }
          }

          List<AppUser> nearbyUsers = [];

          for (QueryDocumentSnapshot doc in snapshot.docs) {
            // Skip current user
            if (doc.id == user.uid) continue;

            try {
              AppUser appUser = AppUser.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              );

              // Filter by time (last 15 minutes)
              if (appUser.lastSeen.isBefore(
                DateTime.now().subtract(const Duration(minutes: 15)),
              )) {
                continue;
              }

              // Calculate distance
              double distance = Geolocator.distanceBetween(
                currentLocation.latitude,
                currentLocation.longitude,
                appUser.location.latitude,
                appUser.location.longitude,
              );

              // Add user if within radius
              if (distance <= radiusInMeters) {
                nearbyUsers.add(appUser);
              }
            } catch (e) {
              print('Error processing user ${doc.id}: $e');
            }
          }

          return nearbyUsers;
        });
  }

  // Start location tracking (call this when app starts)
  static Future<void> startLocationTracking() async {
    await updateUserLocation();

    // Update location every 30 seconds
    Stream.periodic(const Duration(seconds: 30)).listen((_) {
      updateUserLocation();
    });
  }

  // Stop location tracking (call this when app closes)
  static Future<void> stopLocationTracking() async {
    await markUserOffline();
  }
}
