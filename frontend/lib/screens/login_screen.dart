import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// Responsive layout helper class
class ResponsiveLayout {
  static const double _mobileBreakpoint = 600;
  static const double _tabletBreakpoint = 900;
  
  static bool isMobile(BuildContext context) => 
      MediaQuery.of(context).size.width < _mobileBreakpoint;
  
  static bool isTablet(BuildContext context) => 
      MediaQuery.of(context).size.width >= _mobileBreakpoint && 
      MediaQuery.of(context).size.width < _tabletBreakpoint;
  
  static bool isDesktop(BuildContext context) => 
      MediaQuery.of(context).size.width >= _tabletBreakpoint;
  
  static double getSpacing(BuildContext context) {
    if (isMobile(context)) return 12;
    if (isTablet(context)) return 18;
    return 24;
  }
  
  static double getPadding(BuildContext context) {
    if (isMobile(context)) return 8;
    if (isTablet(context)) return 12;
    return 16;
  }
  
  static double getFontSize(BuildContext context, {double baseSize = 16}) {
    if (isMobile(context)) return baseSize * 0.8;
    if (isTablet(context)) return baseSize * 0.9;
    return baseSize;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Login',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: ResponsiveLayout.getFontSize(context, baseSize: 20),
          ),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Header image
            Container(
              width: ResponsiveLayout.isMobile(context) 
                  ? MediaQuery.of(context).size.width * 0.85  // 85% on mobile
                  : ResponsiveLayout.isTablet(context)
                      ? MediaQuery.of(context).size.width * 0.7   // 70% on tablet
                      : MediaQuery.of(context).size.width * 0.6,  // 60% on desktop
              height: ResponsiveLayout.isMobile(context)
                  ? MediaQuery.of(context).size.height * 0.25  // 25% on mobile
                  : ResponsiveLayout.isTablet(context)
                      ? MediaQuery.of(context).size.height * 0.3   // 30% on tablet
                      : MediaQuery.of(context).size.height * 0.35, // 35% on desktop
              margin: EdgeInsets.only(bottom: ResponsiveLayout.getSpacing(context) * 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/header.jpeg',
                  fit: BoxFit.contain, // Changed from BoxFit.cover to prevent cropping
                ),
              ),
            ),
            // Sign in button
            ElevatedButton(
              onPressed: () => _signInWithGoogle(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF39FF14), // Neon green
                foregroundColor: Colors.black, // Text color
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveLayout.getSpacing(context) * 2, 
                  vertical: ResponsiveLayout.getSpacing(context) * 1.2
                ),
                textStyle: TextStyle(
                  fontSize: ResponsiveLayout.getFontSize(context, baseSize: 18), 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 1.0
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                shadowColor: const Color(0xFF39FF14),
                elevation: 10,
              ),
              child: const Text('Sign in with Google'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      // Create a GoogleAuthProvider instance
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      
      googleProvider.addScope('email');
      googleProvider.addScope('profile');
      
      // Sign in with popup for web only
      UserCredential result = await FirebaseAuth.instance.signInWithPopup(googleProvider);

      final user = result.user;
      if (user != null) {
        try {
          // Update user online status via backend function
          final callable = FirebaseFunctions.instance.httpsCallable('updateUserOnlineStatus');
          await callable.call();
        } catch (functionError) {
          print('Error calling updateUserOnlineStatus: $functionError');
          // Don't throw here - user is still signed in successfully
        }
      }
    } catch (e) {
      print('Sign-in error: $e');
      // Handle sign-in errors
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Sign In Error', style: TextStyle(color: Color(0xFF39FF14))),
            content: Text('Failed to sign in: ${e.toString()}', style: const TextStyle(color: Colors.white)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK', style: TextStyle(color: Color(0xFF39FF14))),
              ),
            ],
          ),
        );
      }
    }
  }
}

