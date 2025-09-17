import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:tapzee/widgets/app_logo.dart';
import 'package:tapzee/services/user_location_service.dart';
import 'package:tapzee/services/location_testing_service.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
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

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  User? _user;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isEditing = false;

  // Location-related fields
  Position? _currentPosition;
  DateTime? _lastLocationUpdate;
  bool _isLoadingLocation = false;
  String? _locationError;

  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _user = _auth.currentUser;
      if (_user != null) {
        // Try to load additional profile data from Firestore
        try {
          DocumentSnapshot profileDoc = await _firestore
              .collection('users')
              .doc(_user!.uid)
              .get();

          if (profileDoc.exists) {
            _userProfile = profileDoc.data() as Map<String, dynamic>?;
          } else {
            // Create initial profile document
            _userProfile = {
              'displayName': _user!.displayName ?? '',
              'email': _user!.email ?? '',
              'bio': '',
              'joinedAt': FieldValue.serverTimestamp(),
              'photoURL': _user!.photoURL ?? '',
            };
            await _firestore
                .collection('users')
                .doc(_user!.uid)
                .set(_userProfile!);
          }
        } catch (e) {
          print('Error loading profile: $e');
          // Fallback to basic user info
          _userProfile = {
            'displayName': _user!.displayName ?? '',
            'email': _user!.email ?? '',
            'bio': '',
            'photoURL': _user!.photoURL ?? '',
          };
        }

        _displayNameController.text = _userProfile!['displayName'] ?? '';
        _bioController.text = _userProfile!['bio'] ?? '';
      }
    } catch (e) {
      print('Error loading user profile: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic> updatedProfile = {
        'displayName': _displayNameController.text.trim(),
        'bio': _bioController.text.trim(),
        'email': _user!.email,
        'photoURL': _user!.photoURL ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('users')
          .doc(_user!.uid)
          .update(updatedProfile);

      // Also update Firebase Auth display name if changed
      if (_displayNameController.text.trim() != _user!.displayName) {
        await _user!.updateDisplayName(_displayNameController.text.trim());
      }

      setState(() {
        _userProfile = {..._userProfile!, ...updatedProfile};
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.logout, color: Colors.red.shade600),
            const SizedBox(width: 8),
            const Text('Sign Out'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to sign out?'),
            SizedBox(height: 8),
            Text(
              'You will need to select your Google account again when signing back in.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Close the confirmation dialog first
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }

              // Show loading dialog on the root navigator so it isn't tied to this route
              final rootNavigator = Navigator.of(context, rootNavigator: true);
              showDialog(
                context: context,
                useRootNavigator: true,
                barrierDismissible: false,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Text('Signing out...'),
                    ],
                  ),
                ),
              );

              var navigated = false;
              try {
                // Mark user as offline and clean up location data
                await UserLocationService.stopLocationTracking();

                // Sign out from Google to clear account selection
                final googleSignIn = GoogleSignIn();
                if (await googleSignIn.isSignedIn()) {
                  await googleSignIn.disconnect();
                  await googleSignIn.signOut();
                }

                // Sign out from Firebase
                await _auth.signOut();

                // Wait a short moment for cleanup (kept small)
                await Future.delayed(const Duration(milliseconds: 300));

                if (mounted) {
                  // Close the loading dialog using rootNavigator
                  try {
                    if (rootNavigator.mounted && rootNavigator.canPop()) {
                      rootNavigator.pop();
                    }
                  } catch (_) {}

                  // Ensure we only navigate once
                  if (!navigated) {
                    navigated = true;
                    if (rootNavigator.mounted) {
                      rootNavigator.pushNamedAndRemoveUntil(
                        '/login',
                        (route) => false,
                      );
                    }
                  }
                }
              } catch (e) {
                // Close loading dialog and show error
                try {
                  if (rootNavigator.mounted && rootNavigator.canPop()) {
                    rootNavigator.pop();
                  }
                } catch (_) {}

                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Error'),
                      content: Text('Failed to sign out: ${e.toString()}'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  // Location-related methods
  Future<void> _getCurrentLocation() async {
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
          _lastLocationUpdate = DateTime.now();
        });
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError =
              'Location services are disabled. Please enable location in your browser or use custom location for testing.';
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
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      setState(() {
        _isLoadingLocation = false;
        _lastLocationUpdate = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _locationError =
            'Failed to get current location: ${e.toString()}. This is common in web browsers. Please use custom location for testing or allow location access when prompted.';
        _isLoadingLocation = false;
      });
    }
  }

  String _formatLastUpdate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 30) {
      return 'Just now';
    } else if (difference.inMinutes < 1) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
          if (_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _displayNameController.text =
                      _userProfile!['displayName'] ?? '';
                  _bioController.text = _userProfile!['bio'] ?? '';
                });
              },
            ),
            IconButton(icon: const Icon(Icons.check), onPressed: _saveProfile),
          ],
        ],
      ),
      body: _user == null
          ? const Center(child: Text('No user logged in'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Location Testing Button (moved from FAB)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.gps_fixed, color: Colors.orange),
                      label: const Text(
                        'Location Testing',
                        style: TextStyle(color: Colors.orange),
                      ),
                      onPressed: _showLocationTestingDialog,
                    ),
                  ),
                  // Profile Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Profile Picture
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white,
                          child: _userProfile!['photoURL']?.isNotEmpty == true
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Image.network(
                                    _userProfile!['photoURL']!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const AppLogo.large();
                                    },
                                  ),
                                )
                              : const AppLogo.large(),
                        ),
                        const SizedBox(height: 16),

                        // Display Name
                        if (_isEditing)
                          TextField(
                            controller: _displayNameController,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: 'Display Name',
                              hintStyle: TextStyle(color: Colors.white70),
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white70),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          )
                        else
                          Text(
                            _userProfile!['displayName']?.isNotEmpty == true
                                ? _userProfile!['displayName']!
                                : 'User',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),

                        const SizedBox(height: 8),

                        // Email
                        Text(
                          _userProfile!['email'] ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Profile Information Cards
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person, color: Colors.blue.shade600),
                              const SizedBox(width: 8),
                              const Text(
                                'About Me',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          if (_isEditing)
                            TextField(
                              controller: _bioController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Tell us about yourself...',
                                border: OutlineInputBorder(),
                              ),
                            )
                          else
                            Text(
                              _userProfile!['bio']?.isNotEmpty == true
                                  ? _userProfile!['bio']!
                                  : 'No bio available',
                              style: const TextStyle(fontSize: 16),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Location Information Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: Colors.blue.shade600,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Current Location',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: _getCurrentLocation,
                                tooltip: 'Refresh Location',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          if (_isLoadingLocation)
                            const Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Getting location...'),
                              ],
                            )
                          else if (_locationError != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                border: Border.all(color: Colors.red.shade200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade600,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _locationError!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (_currentPosition != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: LocationTestingService.useCustomLocation
                                    ? Colors.orange.shade50
                                    : Colors.green.shade50,
                                border: Border.all(
                                  color:
                                      LocationTestingService.useCustomLocation
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
                                  const SizedBox(height: 8),
                                  Text(
                                    'Coordinates: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                                    style: TextStyle(
                                      color:
                                          LocationTestingService
                                              .useCustomLocation
                                          ? Colors.orange.shade600
                                          : Colors.green.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (_lastLocationUpdate != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Updated: ${_formatLastUpdate(_lastLocationUpdate!)}',
                                      style: TextStyle(
                                        color:
                                            LocationTestingService
                                                .useCustomLocation
                                            ? Colors.orange.shade500
                                            : Colors.green.shade500,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                  if (LocationTestingService
                                      .useCustomLocation) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '💡 Using custom location for testing',
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
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Account Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue.shade600),
                              const SizedBox(width: 8),
                              const Text(
                                'Account Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          _buildInfoRow('User ID', _user!.uid),
                          _buildInfoRow(
                            'Email Verified',
                            _user!.emailVerified ? 'Yes' : 'No',
                          ),
                          if (_userProfile!['joinedAt'] != null)
                            _buildInfoRow(
                              'Joined',
                              _formatDate(_userProfile!['joinedAt']),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';

    try {
      if (timestamp is Timestamp) {
        DateTime date = timestamp.toDate();
        return '${date.day}/${date.month}/${date.year}';
      }
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }
}
