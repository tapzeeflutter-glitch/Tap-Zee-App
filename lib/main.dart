import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tapzee/services/chat_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tapzee/firebase_options.dart';
import 'package:tapzee/screens/auth_gate.dart';
import 'package:tapzee/screens/main_navigation_screen.dart';
import 'package:tapzee/screens/permissions_setup_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:tapzee/models/user_profile.dart';
import 'package:tapzee/models/room.dart';
import 'package:tapzee/models/attendance.dart';
import 'package:tapzee/models/message.dart';
import 'package:tapzee/services/hive_service.dart';
import 'package:tapzee/adapters/geopoint_adapter.dart';
import 'package:tapzee/adapters/timestamp_adapter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  try {
    // Initialize Firebase only if not already initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    print('Firebase initialization error: $e');
    // Continue with app initialization even if Firebase fails
  }

  // Initialize Hive and register adapters
  await Hive.initFlutter();
  Hive.registerAdapter(UserProfileAdapter());
  Hive.registerAdapter(RoomAdapter());
  Hive.registerAdapter(AttendanceAdapter());
  Hive.registerAdapter(MessageAdapter());
  Hive.registerAdapter(GeoPointAdapter()); // Register GeoPointAdapter
  Hive.registerAdapter(TimestampAdapter()); // Register TimestampAdapter

  await HiveService.init(); // Initialize HiveService

  runApp(
    ChangeNotifierProvider(create: (_) => ChatProvider(), child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tap Zee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.lightBlue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.lightBlue,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.lightBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.lightBlue,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Colors.lightBlue,
          unselectedItemColor: Colors.grey,
          backgroundColor: Colors.white,
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.lightBlue),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Colors.lightBlue,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Authentication Error',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(snapshot.error.toString()),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // Force rebuild
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyApp(),
                          ),
                        );
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasData) {
            // User is logged in, check if permissions are set up
            return FutureBuilder<bool>(
              future: _checkLocationPermission(),
              builder: (context, permissionSnapshot) {
                if (permissionSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final hasLocationPermission = permissionSnapshot.data ?? false;
                if (hasLocationPermission) {
                  return MainNavigationScreen(); // User has permissions, go to main navigation
                } else {
                  return const PermissionsSetupScreen(); // Need to set up permissions
                }
              },
            );
          }
          return const AuthGate(); // No user logged in
        },
      ),
    );
  }
}
