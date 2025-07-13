import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/game_table_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix App Quest',
      theme: ThemeData(
        fontFamily: 'ShareTechMono',
        primaryColor: const Color(0xFF00FF41), // Matrix green  
        scaffoldBackgroundColor: Colors.black,
        brightness: Brightness.dark,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF00FF41)),
          bodyMedium: TextStyle(color: Color(0xFF00FF41)),
          bodySmall: TextStyle(color: Color(0xFF00FF41)),
          titleLarge: TextStyle(color: Colors.white),
          titleMedium: TextStyle(color: Colors.white),
          titleSmall: TextStyle(color: Colors.white),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Color(0xFF00FF41),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00FF41),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            elevation: 8,
            shadowColor: Color(0xFF00FF41),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF00FF41), width: 1.5),
          ),
          elevation: 6,
          shadowColor: const Color(0xFF00FF41).withOpacity(0.2),
        ),
      ),
      darkTheme: ThemeData(
        fontFamily: 'ShareTechMono',
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00FF41),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Color(0xFF00FF41),
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF00FF41), width: 1.5),
          ),
          elevation: 6,
          shadowColor: const Color(0xFF00FF41).withOpacity(0.2),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  @override
  _AuthGateState createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  User? _user;
  Widget? _screen;
  bool _loading = true;
  Stream<User?>? _authStream;
  late final StreamSubscription<User?> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
    _authSubscription = _authStream!.listen((user) async {
      setState(() {
        _user = user;
      });
      
      if (user == null) {
        // User signed out - immediately show login screen without loading
        setState(() {
          _screen = LoginScreen();
          _loading = false;
        });
      } else {
        // User signed in - show loading and fetch games
        setState(() {
          _loading = true;
        });
        
        try {
          // Fetch the user's games from Realtime Database
          final DatabaseReference gamesRef = FirebaseDatabase.instance.ref('games');
          final DatabaseEvent event = await gamesRef.once();
          
          List<Map<String, dynamic>> activeGames = [];
          List<Map<String, dynamic>> finishedGames = [];
          
          if (event.snapshot.exists && event.snapshot.value != null) {
            final gamesValue = event.snapshot.value;
            final userId = user.uid;
            
            if (gamesValue != null) {
              final gamesData = _safeMapConversion(gamesValue);
              gamesData.forEach((gameId, gameData) {
                if (gameData != null) {
                  final game = _safeMapConversion(gameData);
                  final players = List<String>.from(game['players'] ?? []);
                  
                  if (players.contains(userId)) {
                    if (game['status'] == 'active') {
                      activeGames.add({'id': gameId, 'data': game});
                    } else if (game['status'] == 'finished') {
                      final exitedPlayers = List<String>.from(game['exitedPlayers'] ?? []);
                      if (!exitedPlayers.contains(userId)) {
                        finishedGames.add({'id': gameId, 'data': game});
                      }
                    }
                  }
                }
              });
            }
          }

          Widget screen;
          if (activeGames.isNotEmpty) {
            screen = GameTableScreen(gameId: activeGames.first['id']);
          } else if (finishedGames.isNotEmpty) {
            screen = GameTableScreen(gameId: finishedGames.first['id']);
          } else {
            screen = LobbyScreen();
          }
          setState(() {
            _screen = screen;
            _loading = false;
          });
        } catch (e) {
          print('Error fetching games: $e');
          // If there's an error (like permission denied), just go to lobby
          setState(() {
            _screen = LobbyScreen();
            _loading = false;
          });
        }
      }
    });
  }

  // Safe conversion from Firebase Realtime Database value to Map<String, dynamic>
  Map<String, dynamic> _safeMapConversion(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _screen ?? const SizedBox.shrink();
  }
}
