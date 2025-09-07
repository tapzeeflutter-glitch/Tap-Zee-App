import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tapzee/widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  String? _error;
  bool _isLoading = false;

  // Configure Google Sign-in for different platforms
  GoogleSignIn get _googleSignInInstance {
    if (kIsWeb) {
      final clientId =
          dotenv.env['GOOGLE_CLIENT_ID'] ??
          'YOUR_GOOGLE_CLIENT_ID_HERE.apps.googleusercontent.com';
      return GoogleSignIn(
        clientId: clientId,
        // Force account selection on web
      );
    } else {
      return GoogleSignIn(
        // Force account selection on mobile
        signInOption: SignInOption.standard,
      );
    }
  }

  Future<void> _googleSignIn() async {
    if (_isLoading) return;

    // Check if Google Sign-in is properly configured for web
    if (kIsWeb) {
      final clientId =
          dotenv.env['GOOGLE_CLIENT_ID'] ??
          'YOUR_GOOGLE_CLIENT_ID_HERE.apps.googleusercontent.com';
      if (clientId.startsWith('YOUR_GOOGLE_CLIENT_ID_HERE')) {
        setState(() {
          _error =
              'Google Sign-in is not configured for web. Please update GOOGLE_CLIENT_ID in .env file. See .env file for instructions.';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Always sign out first to force account selection
      await _googleSignInInstance.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignInInstance
          .signIn();
      if (googleUser == null) {
        // User cancelled the sign-in
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);

      // Navigate back is handled by the StreamBuilder in main.dart.
      // Avoid programmatic navigation here to prevent double-routing.
      // Keep the current route stack intact; UI will rebuild based on auth state.
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'account-exists-with-different-credential':
            _error =
                'An account already exists with the same email address but different sign-in credentials.';
            break;
          case 'invalid-credential':
            _error = 'The credential received is malformed or has expired.';
            break;
          case 'operation-not-allowed':
            _error = 'Google sign-in is not enabled for this project.';
            break;
          case 'user-disabled':
            _error = 'This account has been disabled.';
            break;
          default:
            _error = e.message ?? 'An error occurred during Google sign-in';
        }
      });
    } catch (e) {
      setState(() {
        String errorMessage = e.toString();

        // Handle common Android Google Sign-in errors
        if (errorMessage.contains('DEVELOPER_ERROR') ||
            errorMessage.contains('10')) {
          _error =
              'Google Sign-in configuration error. Please check:\n'
              '1. google-services.json file is in android/app/\n'
              '2. SHA-1 fingerprint is added to Firebase Console\n'
              '3. Package name matches Firebase configuration\n'
              'See GOOGLE_SIGNIN_ANDROID_SETUP.md for details.';
        } else if (errorMessage.contains('SIGN_IN_CANCELLED') ||
            errorMessage.contains('12501')) {
          _error = 'Sign-in was cancelled by user.';
        } else if (errorMessage.contains('NETWORK_ERROR') ||
            errorMessage.contains('7')) {
          _error = 'Network error. Please check your internet connection.';
        } else if (errorMessage.contains('INVALID_ACCOUNT') ||
            errorMessage.contains('5')) {
          _error =
              'Invalid account. Please try with a different Google account.';
        } else {
          _error = 'Google sign-in failed: $errorMessage';
        }
      });
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // App Logo
              const AnimatedAppLogo(size: 120),
              const SizedBox(height: 200),

              Text(
                'Welcome to Tap Zee',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Text(
                'Sign in with your Google account to continue',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Error message
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(20.0),
                  margin: const EdgeInsets.only(bottom: 24.0),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
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

              // Google Sign-in Button
              SizedBox(
                width: 200,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _googleSignIn,
                  icon: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 24),
                  label: Text(
                    _isLoading ? 'Signing in...' : 'Sign in with Google',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
