import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math';
import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'game_table_screen.dart';
import '../widgets/game_rules_dialog.dart';
import 'login_screen.dart';

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
  
  static double getCardWidth(BuildContext context) {
    if (isMobile(context)) return 280;
    if (isTablet(context)) return 320;
    return 400;
  }
  
  static double getCardHeight(BuildContext context) {
    if (isMobile(context)) return 120;
    if (isTablet(context)) return 140;
    return 160;
  }
  
  static EdgeInsets getCardPadding(BuildContext context) {
    final padding = getPadding(context);
    return EdgeInsets.all(padding);
  }
  
  static EdgeInsets getCardMargin(BuildContext context) {
    final spacing = getSpacing(context);
    return EdgeInsets.symmetric(vertical: spacing * 0.5);
  }
}

// Lobby data class to prevent unnecessary rebuilds
class LobbyData {
  final String id;
  final String creatorName;
  final List<String> players;
  final Map<String, dynamic> playerNames;
  final bool isFull;
  final bool isUserCreator;
  final bool isUserInLobby;

  LobbyData({
    required this.id,
    required this.creatorName,
    required this.players,
    required this.playerNames,
    required this.isFull,
    required this.isUserCreator,
    required this.isUserInLobby,
  });

  factory LobbyData.fromRealtimeDatabase(String key, Map<String, dynamic> data, String currentUserId) {
    final playersData = data['players'];
    final players = playersData is List 
        ? List<String>.from(playersData) 
        : <String>[];
    
    final playerNamesData = data['playerNames'];
    final playerNames = playerNamesData is Map
        ? Map<String, dynamic>.from(playerNamesData)
        : <String, dynamic>{};
    
    final creatorId = data['creatorId'] as String?;
    
    return LobbyData(
      id: key,
      creatorName: data['creatorName'] ?? 'Unknown',
      players: players,
      playerNames: playerNames,
      isFull: players.length >= 4,
      isUserCreator: creatorId == currentUserId,
      isUserInLobby: players.contains(currentUserId),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LobbyData &&
        other.id == id &&
        other.creatorName == creatorName &&
        other.isFull == isFull &&
        other.isUserCreator == isUserCreator &&
        other.isUserInLobby == isUserInLobby &&
        _deepEquals(other.players, players) &&
        _deepEquals(other.playerNames, playerNames);
  }

  @override
  int get hashCode => Object.hash(
    id,
    creatorName,
    isFull,
    isUserCreator,
    isUserInLobby,
    Object.hashAll(players),
    Object.hashAll(playerNames.keys),
  );

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == b) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (var key in a.keys) {
        if (!b.containsKey(key) || a[key] != b[key]) return false;
      }
      return true;
    }
    return false;
  }
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({Key? key}) : super(key: key);

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _isRedirecting = false;
  bool _isCreatingLobby = false;
  bool _loadingScores = false;
  bool _isSigningOut = false;
  Timer? _redirectTimer;
  List<LobbyData> _lobbies = [];
  List<Map<String, dynamic>> _userGames = [];
  List<Map<String, dynamic>> _playerScores = [];
  StreamSubscription<DatabaseEvent>? _lobbiesSubscription;
  StreamSubscription<DatabaseEvent>? _gamesSubscription;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _loadPlayerScores();
    // Set up a periodic check for active games as backup
    _redirectTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isRedirecting && mounted) {
        _checkForActiveGame();
      }
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _lobbiesSubscription?.cancel();
    _gamesSubscription?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen to lobbies in Realtime Database
    final lobbiesRef = FirebaseDatabase.instance
        .ref('lobbies')
        .orderByChild('status')
        .equalTo('waiting');
    
    _lobbiesSubscription = lobbiesRef.onValue.listen((DatabaseEvent event) {
      try {
        if (event.snapshot.exists) {
          final lobbiesValue = event.snapshot.value;
          if (lobbiesValue != null) {
            final lobbiesData = _safeMapConversion(lobbiesValue);
            final newLobbies = lobbiesData.entries
                .map((entry) => LobbyData.fromRealtimeDatabase(
                    entry.key, _safeMapConversion(entry.value), user.uid))
                .where((lobby) => lobby.players.length <= 4) // Filter out invalid lobbies
                .toList();
            
            // Sort by creation time (newest first)
            newLobbies.sort((a, b) => b.id.compareTo(a.id));
            
            // Only update if there are actual changes
            if (!_deepEquals(_lobbies, newLobbies)) {
              if (mounted) {
                setState(() {
                  _lobbies = newLobbies;
                });
              }
            }
          } else {
            if (mounted) {
              setState(() {
                _lobbies = [];
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _lobbies = [];
            });
          }
        }
      } catch (e) {
        print('Error updating lobbies: $e');
      }
    }, onError: (error) {
      print('Lobbies stream error: $error');
    });

          // Listen to user's games in Realtime Database
      final gamesRef = FirebaseDatabase.instance.ref('games');
    
    _gamesSubscription = gamesRef.onValue.listen((DatabaseEvent event) {
      try {
        if (event.snapshot.exists) {
          final gamesValue = event.snapshot.value;
          if (gamesValue != null) {
            final gamesData = _safeMapConversion(gamesValue);
            final newUserGames = <Map<String, dynamic>>[];
            
            for (final entry in gamesData.entries) {
              final gameData = _safeMapConversion(entry.value);
              final players = List<String>.from(gameData['players'] ?? []);
              if (players.contains(user.uid)) {
                newUserGames.add({
                  'id': entry.key,
                  ...gameData,
                });
              }
            }
            
            // Only update if there are actual changes
            if (!_deepEquals(_userGames, newUserGames)) {
              if (mounted) {
                setState(() {
                  _userGames = newUserGames;
                });
                
                // Check for active games
                _checkForActiveGameFromGames(newUserGames);
              }
            }
          } else {
            if (mounted) {
              setState(() {
                _userGames = [];
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _userGames = [];
            });
          }
        }
      } catch (e) {
        print('Error updating games: $e');
      }
    }, onError: (error) {
      print('Games stream error: $error');
    });
  }

  bool _deepEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

  void _checkForActiveGameFromGames(List<Map<String, dynamic>> games) {
    if (_isRedirecting) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    for (final gameData in games) {
      final gameStatus = gameData['status'];
      final exitedPlayers = Set<String>.from(gameData['exitedPlayers'] ?? []);
      final currentUser = user.uid;
      
      if ((gameStatus == 'active' || gameStatus == 'resigned' || gameStatus == 'finished') && 
          !exitedPlayers.contains(currentUser)) {
        _redirectToGame(gameData['id']);
        break;
      }
    }
  }

  Future<void> _checkForActiveGame() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final gamesSnapshot = await FirebaseDatabase.instance
          .ref('games')
          .orderByChild('status')
          .equalTo('active')
          .once();
      
      if (gamesSnapshot.snapshot.exists) {
        final gamesValue = gamesSnapshot.snapshot.value;
        if (gamesValue != null) {
          final gamesData = _safeMapConversion(gamesValue);
          for (final entry in gamesData.entries) {
            final gameData = _safeMapConversion(entry.value);
            final players = List<String>.from(gameData['players'] ?? []);
            if (players.contains(user.uid) && !_isRedirecting) {
              _redirectToGame(entry.key);
              break;
            }
          }
        }
      }
    } catch (e) {
      // Ignore errors in backup check
    }
  }

  Future<void> _loadPlayerScores() async {
    if (_loadingScores) return;
    
    setState(() {
      _loadingScores = true;
    });
    
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getPlayerScores');
      final result = await callable.call();
      
      if (result.data != null && result.data['scores'] != null) {
        final scores = List<Map<String, dynamic>>.from(result.data['scores']);
        if (mounted) {
          setState(() {
            _playerScores = scores;
          });
        }
      }
    } catch (e) {
      // Handle error silently for scores
      print('Error loading player scores: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingScores = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    
    setState(() {
      _isSigningOut = true;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable('removeUserOnlineStatus');
          await callable.call();
        } catch (e) {
          // Handle error silently for logout operations
          print('Error removing user online status: $e');
        }
      }
      
      // Sign out from Firebase Auth
      await FirebaseAuth.instance.signOut();
      if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
      
      // The auth state listener in main.dart will handle navigation
      
    } catch (e) {
      print('Error signing out: $e');
      // Reset the loading state if sign out fails
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  Future<void> _createLobby(BuildContext context, String userId, String userName) async {
    if (_isCreatingLobby) return; // Prevent multiple calls
    
    setState(() {
      _isCreatingLobby = true;
    });
    
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('createLobby');
      final result = await callable.call();
      
      if (result.data != null && result.data['lobbyId'] != null) {
        final lobbyId = result.data['lobbyId'];
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingScreen(lobbyId: lobbyId),
          ),
        );
      }
    } catch (e) {
      String errorMessage = 'Failed to create lobby';
      
      if (e.toString().contains('You can create only one lobby')) {
        errorMessage = 'You can create only one lobby';
      } else if (e.toString().contains('unauthenticated')) {
        errorMessage = 'Please sign in to create a lobby';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('Error', style: TextStyle(color: Color(0xFF39FF14))),
          content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Color(0xFF39FF14))),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingLobby = false;
        });
      }
    }
  }

  Future<void> _joinLobby(BuildContext context, String lobbyId, String userId, List<LobbyData> lobbies) async {
    try {
      // Validate lobby still exists and has space before joining
      final lobbySnapshot = await FirebaseDatabase.instance
          .ref('lobbies/$lobbyId')
          .once();
      
      if (!lobbySnapshot.snapshot.exists) {
        throw Exception('Lobby no longer exists');
      }
      
      final lobbyData = _safeMapConversion(lobbySnapshot.snapshot.value);
      final players = List<String>.from(lobbyData['players'] ?? []);
      
      if (players.length >= 4) {
        throw Exception('Lobby is full');
      }
      
      if (lobbyData['status'] != 'waiting') {
        throw Exception('Lobby is no longer accepting players');
      }
      
      final callable = FirebaseFunctions.instance.httpsCallable('joinLobby');
      await callable.call({'lobbyId': lobbyId});
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WaitingScreen(lobbyId: lobbyId),
        ),
      );
    } catch (e) {
      String errorMessage = 'Failed to join lobby';
      
      if (e.toString().contains("Can't join another lobby, please leave your lobby first")) {
        errorMessage = "Can't join another lobby, please leave your lobby first";
      } else if (e.toString().contains('Lobby is full')) {
        errorMessage = 'Lobby is full';
      } else if (e.toString().contains('Lobby not found') || e.toString().contains('Lobby no longer exists')) {
        errorMessage = 'Lobby no longer exists';
      } else if (e.toString().contains('You are already in this lobby')) {
        errorMessage = 'You are already in this lobby';
      } else if (e.toString().contains('Lobby is no longer accepting players')) {
        errorMessage = 'Lobby is no longer accepting players';
      } else if (e.toString().contains('unauthenticated')) {
        errorMessage = 'Please sign in to join a lobby';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('Error', style: TextStyle(color: Color(0xFF39FF14))),
          content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
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

  Widget _buildLeaderboard() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.getSpacing(context),
        vertical: ResponsiveLayout.getSpacing(context) * 0.5,
      ),
      child: Card(
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF39FF14), width: 1.5),
        ),
        elevation: 6,
        shadowColor: const Color(0xFF39FF14).withOpacity(0.2),
        child: Padding(
          padding: ResponsiveLayout.getCardPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.leaderboard,
                    color: const Color(0xFF39FF14),
                    size: ResponsiveLayout.getFontSize(context, baseSize: 20),
                  ),
                  SizedBox(width: ResponsiveLayout.getSpacing(context) * 0.5),
                  Text(
                    'Leaderboard',
                    style: TextStyle(
                      color: const Color(0xFF39FF14),
                      fontSize: ResponsiveLayout.getFontSize(context, baseSize: 18),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_loadingScores)
                    SizedBox(
                      width: ResponsiveLayout.getFontSize(context, baseSize: 16),
                      height: ResponsiveLayout.getFontSize(context, baseSize: 16),
                      child: const CircularProgressIndicator(
                        color: Color(0xFF39FF14),
                        strokeWidth: 2,
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: const Color(0xFF39FF14),
                        size: ResponsiveLayout.getFontSize(context, baseSize: 18),
                      ),
                      onPressed: _loadPlayerScores,
                    ),
                ],
              ),
              SizedBox(height: ResponsiveLayout.getSpacing(context) * 0.7),
              
              // Leaderboard content
              if (_playerScores.isEmpty && !_loadingScores)
                Padding(
                  padding: EdgeInsets.all(ResponsiveLayout.getSpacing(context)),
                  child: Text(
                    'No games played yet!',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14),
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Container(
                  constraints: BoxConstraints(
                    maxHeight: ResponsiveLayout.isMobile(context) ? 200 : 250,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _playerScores.length > 10 ? 10 : _playerScores.length,
                    itemBuilder: (context, index) {
                      final score = _playerScores[index];
                      final playerName = score['playerName'] ?? 'Unknown Player';
                      final wins = score['wins'] ?? 0;
                      final rank = index + 1;
                      
                      // Get rank icon
                      Widget rankWidget;
                      if (rank == 1) {
                        rankWidget = const Icon(Icons.emoji_events, color: Colors.amber, size: 20);
                      } else if (rank == 2) {
                        rankWidget = const Icon(Icons.emoji_events, color: Colors.grey, size: 18);
                      } else if (rank == 3) {
                        rankWidget = const Icon(Icons.emoji_events, color: Colors.brown, size: 16);
                      } else {
                        rankWidget = Text(
                          '$rank',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14),
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }
                      
                      return Container(
                        margin: EdgeInsets.symmetric(vertical: 2),
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveLayout.getSpacing(context) * 0.5,
                          vertical: ResponsiveLayout.getSpacing(context) * 0.3,
                        ),
                        decoration: BoxDecoration(
                          color: rank <= 3 ? const Color(0xFF39FF14).withOpacity(0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: rank <= 3 ? Border.all(
                            color: const Color(0xFF39FF14).withOpacity(0.3),
                            width: 1,
                          ) : null,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 30,
                              child: rankWidget,
                            ),
                            SizedBox(width: ResponsiveLayout.getSpacing(context) * 0.5),
                            Expanded(
                              child: Text(
                                playerName,
                                style: TextStyle(
                                  color: rank <= 3 ? const Color(0xFF39FF14) : Colors.white,
                                  fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14),
                                  fontWeight: rank <= 3 ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '$wins wins',
                              style: TextStyle(
                                color: rank <= 3 ? const Color(0xFF39FF14) : Colors.white70,
                                fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leaveLobby(BuildContext context, String lobbyId, String userId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('leaveLobby');
      await callable.call({'lobbyId': lobbyId});
      
      // If the user is in the waiting room, pop to lobbies
      if (Navigator.canPop(context)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      String errorMessage = 'Failed to leave lobby';
      
      if (e.toString().contains('Lobby not found')) {
        errorMessage = 'Lobby not found';
      } else if (e.toString().contains('You are not in this lobby')) {
        errorMessage = 'You are not in this lobby';
      } else if (e.toString().contains('unauthenticated')) {
        errorMessage = 'Please sign in to leave the lobby';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('Error', style: TextStyle(color: Color(0xFF39FF14))),
          content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
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

  void _redirectToGame(String gameId) {
    if (!_isRedirecting && mounted) {
      setState(() {
        _isRedirecting = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Use pushAndRemoveUntil to clear the entire navigation stack and start fresh
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => GameTableScreen(gameId: gameId),
            ),
            (route) => false,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }
    final name = user.displayName ?? user.email ?? 'User';
    
    // Check if user is in any game and redirect automatically
    if (_userGames.isNotEmpty && !_isRedirecting) {
      for (final gameData in _userGames) {
        final gameStatus = gameData['status'];
        final exitedPlayers = Set<String>.from(gameData['exitedPlayers'] ?? []);
        final currentUser = user.uid;
        
        if ((gameStatus == 'active' || gameStatus == 'resigned' || gameStatus == 'finished') && 
            !exitedPlayers.contains(currentUser)) {
          _redirectToGame(gameData['id']);
          return const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)));
        }
      }
    }

    // Find if user is in any lobby
    String? myLobbyId;
    bool isCreator = false;
    for (final lobby in _lobbies) {
      if (lobby.isUserInLobby) {
        myLobbyId = lobby.id;
        isCreator = lobby.isUserCreator;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Lobbies',
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
        leading: IconButton(
          icon: Icon(
            Icons.info_outline,
            color: const Color(0xFF39FF14),
            size: ResponsiveLayout.getFontSize(context, baseSize: 28),
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => const GameRulesDialog(),
            );
          },
        ),
        actions: [
          ElevatedButton(
            onPressed: _isSigningOut ? null : () => _signOut(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF39FF14),
              foregroundColor: Colors.black,
              padding: ResponsiveLayout.getCardPadding(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              shadowColor: const Color(0xFF39FF14),
              elevation: 6,
            ),
            child: _isSigningOut
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : Text(
                    'Sign out $name',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: ResponsiveLayout.getFontSize(context, baseSize: 16),
                      letterSpacing: 1.1,
                    ),
                  ),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildLeaderboard(),
            Expanded(
              child: _lobbies.isEmpty
                  ? Center(
                      child: Text(
                        'No open lobbies.\nCreate one!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white, 
                          fontSize: ResponsiveLayout.getFontSize(context, baseSize: 20)
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(ResponsiveLayout.getPadding(context)),
                      itemCount: _lobbies.length,
                      itemBuilder: (context, index) {
                        final lobby = _lobbies[index];
                        final playerNames = lobby.players.map((uid) => 
                          lobby.playerNames.containsKey(uid) 
                            ? lobby.playerNames[uid] ?? 'Unknown Player'
                            : 'Unknown Player'
                        ).toList();
                        
                        return Card(
                          key: ValueKey('lobby_${lobby.id}'),
                          color: Colors.grey[900],
                          margin: ResponsiveLayout.getCardMargin(context),
                          child: ListTile(
                            contentPadding: ResponsiveLayout.getCardPadding(context),
                            title: Text(
                              "${lobby.creatorName}'s lobby",
                              style: TextStyle(
                                color: const Color(0xFF39FF14), 
                                fontWeight: FontWeight.bold,
                                fontSize: ResponsiveLayout.getFontSize(context, baseSize: 16),
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${lobby.players.length}/4 players',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(top: ResponsiveLayout.getSpacing(context) * 0.3),
                                  child: Text(
                                    playerNames.isNotEmpty ? playerNames.join(', ') : 'No players',
                                    style: TextStyle(
                                      fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12), 
                                      color: Colors.white54
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (lobby.isUserCreator)
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => WaitingScreen(lobbyId: lobby.id),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.black,
                                      padding: ResponsiveLayout.getCardPadding(context),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      shadowColor: Colors.orange,
                                      elevation: 6,
                                    ),
                                    child: Text(
                                      'Return to your lobby',
                                      style: TextStyle(
                                        fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12),
                                      ),
                                    ),
                                  )
                                else if (lobby.isUserInLobby) ...[
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => WaitingScreen(lobbyId: lobby.id),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.black,
                                      padding: ResponsiveLayout.getCardPadding(context),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      shadowColor: Colors.orange,
                                      elevation: 6,
                                    ),
                                    child: Text(
                                      'Return to lobby',
                                      style: TextStyle(
                                        fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: ResponsiveLayout.getSpacing(context) * 0.7),
                                  ElevatedButton(
                                    onPressed: () => _leaveLobby(context, lobby.id, user.uid),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      padding: ResponsiveLayout.getCardPadding(context),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      shadowColor: Colors.redAccent,
                                      elevation: 6,
                                    ),
                                    child: Text(
                                      'Leave lobby',
                                      style: TextStyle(
                                        fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12),
                                      ),
                                    ),
                                  ),
                                ]
                                else
                                  ElevatedButton(
                                    onPressed: (lobby.isFull || myLobbyId != null)
                                        ? null
                                        : () => _joinLobby(context, lobby.id, user.uid, _lobbies),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF39FF14),
                                      foregroundColor: Colors.black,
                                      padding: ResponsiveLayout.getCardPadding(context),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      shadowColor: const Color(0xFF39FF14),
                                      elevation: 6,
                                    ),
                                    child: Text(
                                      lobby.isFull 
                                          ? 'Full' 
                                          : myLobbyId != null 
                                              ? 'Already in lobby' 
                                              : 'Join Lobby',
                                      style: TextStyle(
                                        fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.all(ResponsiveLayout.getSpacing(context) * 2.7),
              child:             ElevatedButton(
              onPressed: (myLobbyId != null || _isCreatingLobby)
                  ? () {
                      if (_isCreatingLobby) return; // Do nothing if creating
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.black,
                          title: Text(
                            'Notice', 
                            style: TextStyle(
                              color: const Color(0xFF39FF14),
                              fontSize: ResponsiveLayout.getFontSize(context, baseSize: 18),
                            )
                          ),
                          content: Text(
                            isCreator
                                ? 'You can create only one lobby'
                                : 'You are already in a lobby!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(
                                'OK', 
                                style: TextStyle(
                                  color: const Color(0xFF39FF14),
                                  fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14),
                                )
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  : () => _createLobby(context, user.uid, name),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF39FF14),
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveLayout.getSpacing(context) * 3.3, 
                    vertical: ResponsiveLayout.getSpacing(context) * 1.7
                  ),
                  textStyle: TextStyle(
                    fontSize: ResponsiveLayout.getFontSize(context, baseSize: 22), 
                    fontWeight: FontWeight.bold, 
                    letterSpacing: 1.2
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadowColor: const Color(0xFF39FF14),
                  elevation: 10,
                ),
                child: Text(_isCreatingLobby ? 'Creating...' : 'Create Lobby'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WaitingScreen extends StatefulWidget {
  final String lobbyId;
  const WaitingScreen({Key? key, required this.lobbyId}) : super(key: key);

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  bool _isRedirecting = false;
  Timer? _redirectTimer;
  Map<String, dynamic>? _lobbyData;
  List<Map<String, dynamic>> _userGames = [];
  StreamSubscription<DatabaseEvent>? _lobbySubscription;
  StreamSubscription<DatabaseEvent>? _gamesSubscription;
  bool _lobbyExists = true;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    // Set up a periodic check for active games as backup
    _redirectTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isRedirecting && mounted) {
        _checkForActiveGame();
      }
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _lobbySubscription?.cancel();
    _gamesSubscription?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen to lobby in Realtime Database
    final lobbyRef = FirebaseDatabase.instance.ref('lobbies/${widget.lobbyId}');
    
    _lobbySubscription = lobbyRef.onValue.listen((DatabaseEvent event) {
      try {
        if (!event.snapshot.exists) {
          // Lobby was deleted (cancelled)
          if (mounted) {
            setState(() {
              _lobbyExists = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
          }
          return;
        }

        final lobbyValue = event.snapshot.value;
        final newLobbyData = lobbyValue != null ? _safeMapConversion(lobbyValue) : <String, dynamic>{};
        
        // Only update if there are actual changes
        if (!_deepEquals(_lobbyData, newLobbyData)) {
          if (mounted) {
            setState(() {
              _lobbyData = newLobbyData;
            });
          }
        }
      } catch (e) {
        print('Error updating lobby: $e');
      }
    }, onError: (error) {
      print('Lobby stream error: $error');
    });

    // Listen to user's games
    final gamesRef = FirebaseDatabase.instance.ref('games');
    
    _gamesSubscription = gamesRef.onValue.listen((DatabaseEvent event) {
      try {
        if (event.snapshot.exists) {
          final gamesValue = event.snapshot.value;
          if (gamesValue != null) {
            final gamesData = _safeMapConversion(gamesValue);
            final newUserGames = <Map<String, dynamic>>[];
            
            for (final entry in gamesData.entries) {
              final gameData = _safeMapConversion(entry.value);
              final players = List<String>.from(gameData['players'] ?? []);
              if (players.contains(user.uid)) {
                newUserGames.add({
                  'id': entry.key,
                  ...gameData,
                });
              }
            }
            
            // Only update if there are actual changes
            if (!_deepEquals(_userGames, newUserGames)) {
              if (mounted) {
                setState(() {
                  _userGames = newUserGames;
                });
                
                // Check for active games
                _checkForActiveGameFromGames(newUserGames);
              }
            }
          } else {
            if (mounted) {
              setState(() {
                _userGames = [];
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _userGames = [];
            });
          }
        }
      } catch (e) {
        print('Error updating games in waiting screen: $e');
      }
    }, onError: (error) {
      print('Games stream error in waiting screen: $error');
    });
  }

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == b) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (var key in a.keys) {
        if (!b.containsKey(key) || a[key] != b[key]) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return false;
  }

  void _checkForActiveGameFromGames(List<Map<String, dynamic>> games) {
    if (_isRedirecting) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    for (final gameData in games) {
      final gameStatus = gameData['status'];
      final exitedPlayers = Set<String>.from(gameData['exitedPlayers'] ?? []);
      final currentUser = user.uid;
      
      if ((gameStatus == 'active' || gameStatus == 'resigned' || gameStatus == 'finished') && 
          !exitedPlayers.contains(currentUser)) {
        _redirectToGame(gameData['id']);
        break;
      }
    }
  }

  Future<void> _checkForActiveGame() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final gamesSnapshot = await FirebaseDatabase.instance
          .ref('games')
          .orderByChild('status')
          .equalTo('active')
          .once();
      
      if (gamesSnapshot.snapshot.exists) {
        final gamesValue = gamesSnapshot.snapshot.value;
        if (gamesValue != null) {
          final gamesData = _safeMapConversion(gamesValue);
          for (final entry in gamesData.entries) {
            final gameData = _safeMapConversion(entry.value);
            final players = List<String>.from(gameData['players'] ?? []);
            if (players.contains(user.uid) && !_isRedirecting) {
              _redirectToGame(entry.key);
              break;
            }
          }
        }
      }
    } catch (e) {
      // Ignore errors in backup check
    }
  }

  Future<void> _cancelLobby(BuildContext context) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('cancelLobby');
      await callable.call({'lobbyId': widget.lobbyId});
      
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      String errorMessage = 'Failed to cancel lobby';
      
      if (e.toString().contains('Lobby not found')) {
        errorMessage = 'Lobby not found';
      } else if (e.toString().contains('Only the creator can cancel the lobby')) {
        errorMessage = 'Only the creator can cancel the lobby';
      } else if (e.toString().contains('unauthenticated')) {
        errorMessage = 'Please sign in to cancel the lobby';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('Error', style: TextStyle(color: Color(0xFF39FF14))),
          content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
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

  Future<void> _leaveLobby(BuildContext context, String userId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('leaveLobby');
      await callable.call({'lobbyId': widget.lobbyId});
      
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      String errorMessage = 'Failed to leave lobby';
      
      if (e.toString().contains('Lobby not found')) {
        errorMessage = 'Lobby not found';
      } else if (e.toString().contains('You are not in this lobby')) {
        errorMessage = 'You are not in this lobby';
      } else if (e.toString().contains('unauthenticated')) {
        errorMessage = 'Please sign in to leave the lobby';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('Error', style: TextStyle(color: Color(0xFF39FF14))),
          content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
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

  void _redirectToGame(String gameId) {
    if (!_isRedirecting && mounted) {
      setState(() {
        _isRedirecting = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Use pushAndRemoveUntil to clear the entire navigation stack and start fresh
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => GameTableScreen(gameId: gameId),
            ),
            (route) => false,
          );
        }
      });
    }
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
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (!_lobbyExists) {
      return const SizedBox.shrink();
    }

    if (_lobbyData == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            'Waiting for Players',
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
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.info_outline,
              color: const Color(0xFF39FF14),
              size: ResponsiveLayout.getFontSize(context, baseSize: 28),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const GameRulesDialog(),
              );
            },
          ),
        ),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))),
      );
    }

    // Check if user is in any game and redirect automatically
    if (_userGames.isNotEmpty && !_isRedirecting) {
      for (final gameData in _userGames) {
        final gameStatus = gameData['status'];
        final exitedPlayers = Set<String>.from(gameData['exitedPlayers'] ?? []);
        final currentUser = user?.uid ?? '';
        
        if ((gameStatus == 'active' || gameStatus == 'resigned' || gameStatus == 'finished') && 
            !exitedPlayers.contains(currentUser)) {
          _redirectToGame(gameData['id']);
          return const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)));
        }
      }
    }

    final playersData = _lobbyData?['players'];
    final players = playersData is List ? List<String>.from(playersData) : <String>[];
    final creatorId = _lobbyData?['creatorId'] as String?;
    final isCreator = user != null && creatorId == user.uid;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Waiting for Players',
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
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(
            Icons.info_outline,
            color: const Color(0xFF39FF14),
            size: ResponsiveLayout.getFontSize(context, baseSize: 28),
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => const GameRulesDialog(),
            );
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Waiting for players...\n${players.length}/4',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF39FF14),
                fontSize: ResponsiveLayout.getFontSize(context, baseSize: 28),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: ResponsiveLayout.getSpacing(context) * 1.7),
            // Show player names in the lobby
            (() {
              final lobbyPlayerNamesData = _lobbyData?['playerNames'];
              final lobbyPlayerNames = lobbyPlayerNamesData is Map ? Map<String, dynamic>.from(lobbyPlayerNamesData) : <String, dynamic>{};
              final playerNames = players.map((uid) => 
                lobbyPlayerNames.containsKey(uid) 
                  ? lobbyPlayerNames[uid] ?? 'Unknown Player'
                  : 'Unknown Player'
              ).toList();
              return Padding(
                padding: EdgeInsets.only(bottom: ResponsiveLayout.getSpacing(context) * 1.7),
                child: Text(
                  playerNames.isNotEmpty ? 'Players: ${playerNames.join(', ')}' : 'No players',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14), 
                    color: Colors.white70
                  ),
                ),
              );
            })(),
            SizedBox(height: ResponsiveLayout.getSpacing(context) * 1.7),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF39FF14),
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveLayout.getSpacing(context) * 2.7, 
                  vertical: ResponsiveLayout.getSpacing(context) * 1.5
                ),
                textStyle: TextStyle(
                  fontSize: ResponsiveLayout.getFontSize(context, baseSize: 20), 
                  fontWeight: FontWeight.bold
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                shadowColor: const Color(0xFF39FF14),
                elevation: 10,
              ),
              child: const Text('Back to lobbies'),
            ),
            if (isCreator) ...[
              SizedBox(height: ResponsiveLayout.getSpacing(context) * 1.7),
              ElevatedButton(
                onPressed: () => _cancelLobby(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveLayout.getSpacing(context) * 2.7, 
                    vertical: ResponsiveLayout.getSpacing(context) * 1.5
                  ),
                  textStyle: TextStyle(
                    fontSize: ResponsiveLayout.getFontSize(context, baseSize: 20), 
                    fontWeight: FontWeight.bold
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadowColor: Colors.redAccent,
                  elevation: 10,
                ),
                child: const Text('Cancel Lobby'),
              ),
            ]
            else ...[
              SizedBox(height: ResponsiveLayout.getSpacing(context) * 1.7),
              ElevatedButton(
                onPressed: () => _leaveLobby(context, user!.uid),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveLayout.getSpacing(context) * 2.7, 
                    vertical: ResponsiveLayout.getSpacing(context) * 1.5
                  ),
                  textStyle: TextStyle(
                    fontSize: ResponsiveLayout.getFontSize(context, baseSize: 20), 
                    fontWeight: FontWeight.bold
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadowColor: Colors.redAccent,
                  elevation: 10,
                ),
                child: const Text('Leave lobby'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

