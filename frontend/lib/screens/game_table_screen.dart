import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import 'lobby_screen.dart';
import '../widgets/game_rules_dialog.dart';

// Responsive layout helper class
class ResponsiveLayout {
  static const double _mobileBreakpoint = 600;
  static const double _tabletBreakpoint = 900;
  
  // Device type detection
  static bool isMobile(BuildContext context) => 
      MediaQuery.of(context).size.width < _mobileBreakpoint;
  
  static bool isTablet(BuildContext context) => 
      MediaQuery.of(context).size.width >= _mobileBreakpoint && 
      MediaQuery.of(context).size.width < _tabletBreakpoint;
  
  static bool isDesktop(BuildContext context) => 
      MediaQuery.of(context).size.width >= _tabletBreakpoint;
  
  // Screen dimensions
  static double getScreenWidth(BuildContext context) => MediaQuery.of(context).size.width;
  static double getScreenHeight(BuildContext context) => MediaQuery.of(context).size.height;
  
  // Responsive sizing based on device type - maintaining same structure
  static double getCardWidth(BuildContext context) {
    final screenWidth = getScreenWidth(context);
    if (isMobile(context)) {
      // On mobile, cards should be smaller and fit the screen
      return (screenWidth - 40) / 4; // 4 cards visible at once with margins
    }
    if (isTablet(context)) {
      return 100;
    }
    return 130; // Larger cards on desktop
  }
  
  static double getCardHeight(BuildContext context) {
    final cardWidth = getCardWidth(context);
    return cardWidth * 1.4; // Maintain aspect ratio
  }
  
  static double getPlayerCircleSize(BuildContext context) {
    if (isMobile(context)) return 40;
    if (isTablet(context)) return 50;
    return 70; // Larger circles on desktop
  }
  
  static double getSpacing(BuildContext context) {
    if (isMobile(context)) return 8;
    if (isTablet(context)) return 12;
    return 20; // More spacing on desktop
  }
  
  static double getPadding(BuildContext context) {
    if (isMobile(context)) return 4;
    if (isTablet(context)) return 8;
    return 16; // More padding on desktop
  }
  
  static double getFontSize(BuildContext context, {double baseSize = 16}) {
    if (isMobile(context)) return baseSize * 0.7;
    if (isTablet(context)) return baseSize * 0.85;
    return baseSize; // Full size on desktop
  }
  
  static double getHeaderFontSize(BuildContext context) {
    if (isMobile(context)) return 14;
    if (isTablet(context)) return 16;
    return 20; // Larger header on desktop
  }
  
  static EdgeInsets getCardMargin(BuildContext context) {
    final spacing = getSpacing(context);
    return EdgeInsets.symmetric(horizontal: spacing * 0.2);
  }
  
  static EdgeInsets getCardPadding(BuildContext context) {
    final padding = getPadding(context);
    return EdgeInsets.symmetric(horizontal: padding * 0.5, vertical: padding * 0.3);
  }
  
  // Layout constraints
  static double getMaxHandWidth(BuildContext context) {
    final screenWidth = getScreenWidth(context);
    if (isMobile(context)) {
      return screenWidth - 20; // Leave small margins
    }
    return screenWidth * 0.8;
  }
  
  static double getMaxPileWidth(BuildContext context) {
    final screenWidth = getScreenWidth(context);
    if (isMobile(context)) {
      return screenWidth * 0.6; // Piles take 60% of screen width on mobile
    }
    return screenWidth * 0.4;
  }
  
  // Safe area handling
  static EdgeInsets getSafePadding(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.padding;
  }
}

// Game state data class to prevent unnecessary rebuilds
class GameState {
  final String status;
  final List<String> playerOrder;
  final int currentTurn;
  final Map<String, dynamic> hands;
  final List<dynamic> burned;
  final List<dynamic> unused;
  final List<dynamic> appDeck;
  final List<dynamic> appPile;
  final Map<String, dynamic>? playerNames;
  final Map<String, dynamic>? pendingAttack;
  final Map<String, dynamic>? currentMessage;
  final String? winner;
  final String? resignedBy;
  final List<String>? resignedPlayers;
  final List<String>? exitedPlayers;

  GameState({
    required this.status,
    required this.playerOrder,
    required this.currentTurn,
    required this.hands,
    required this.burned,
    required this.unused,
    required this.appDeck,
    required this.appPile,
    this.playerNames,
    this.pendingAttack,
    this.currentMessage,
    this.winner,
    this.resignedBy,
    this.resignedPlayers,
    this.exitedPlayers,
  });

  factory GameState.fromRealtimeDatabase(Map<String, dynamic> data) {
    return GameState(
      status: data['status'] ?? 'active',
      playerOrder: _safeStringListConversion(data['playerOrder'] ?? data['players'] ?? []),
      currentTurn: data['currentTurn'] ?? 0,
      hands: _safeMapConversion(data['hands'] ?? {}),
      burned: _safeListConversion(data['burned'] ?? []),
      unused: _safeListConversion(data['unused'] ?? []),
      appDeck: _safeListConversion(data['appDeck'] ?? []),
      appPile: _safeListConversion(data['appPile'] ?? []),
      playerNames: data['playerNames'] != null ? _safeMapConversion(data['playerNames']) : null,
      pendingAttack: data['pendingAttack'] != null ? _safeMapConversion(data['pendingAttack']) : null,
      currentMessage: data['currentMessage'] != null ? _safeMapConversion(data['currentMessage']) : null,
      winner: data['winner'],
      resignedBy: data['resignedBy'],
      resignedPlayers: data['resignedPlayers'] != null ? _safeStringListConversion(data['resignedPlayers']) : null,
      exitedPlayers: data['exitedPlayers'] != null ? _safeStringListConversion(data['exitedPlayers']) : null,
    );
  }

  // Safe conversion from Firebase Realtime Database value to Map<String, dynamic>
  static Map<String, dynamic> _safeMapConversion(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  // Safe conversion from Firebase Realtime Database value to List<dynamic>
  static List<dynamic> _safeListConversion(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return List<dynamic>.from(value);
    }
    // Handle Firebase Realtime Database Map format (index-based)
    if (value is Map) {
      try {
        final sortedKeys = value.keys.toList()..sort();
        return sortedKeys.map((key) => value[key]).toList();
      } catch (e) {
        print('Error converting Map to List: $e');
        return [];
      }
    }
    return [];
  }

  // Safe conversion from Firebase Realtime Database value to List<String>
  static List<String> _safeStringListConversion(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return List<String>.from(value);
    }
    return [];
  }

  // Calculate derived data
  Map<String, int> get playerPoints {
    Map<String, int> points = {for (var uid in playerOrder) uid: 0};
    
    // Debug: Log the appPile data
    print('Frontend appPile data: ${appPile.length} items');
    for (int i = 0; i < appPile.length; i++) {
      print('  appPile[$i]: ${appPile[i]} (type: ${appPile[i].runtimeType})');
    }
    
    for (var card in appPile) {
      // Debug: Log each card processing
      print('Processing card: $card (type: ${card.runtimeType})');
      
      if (card is Map<String, dynamic> && 
          card['type'] == 'app' && 
          card['owner'] != null && 
          card['owner'] is String) {
        final owner = card['owner'] as String;
        final value = (card['value'] is int) ? card['value'] as int : 0;
        points[owner] = (points[owner] ?? 0) + value;
        
        print('  → Player $owner gets $value points from app card');
      } else if (card is Map) {
        // Try to convert non-Map<String, dynamic> to proper format
        final Map<String, dynamic> convertedCard = Map<String, dynamic>.from(card);
        print('  → Converted card: $convertedCard');
        
        if (convertedCard['type'] == 'app' && 
            convertedCard['owner'] != null && 
            convertedCard['owner'] is String) {
          final owner = convertedCard['owner'] as String;
          final value = (convertedCard['value'] is int) ? convertedCard['value'] as int : 0;
          points[owner] = (points[owner] ?? 0) + value;
          
          print('  → Player $owner gets $value points from converted app card');
        }
      }
    }
    
    print('Final points calculation: $points');
    return points;
  }

  Map<String, List<Map<String, dynamic>>> get playerApps {
    Map<String, List<Map<String, dynamic>>> apps = {for (var uid in playerOrder) uid: []};
    for (var card in appPile) {
      if (card is Map<String, dynamic> && 
          card['type'] == 'app' && 
          card['owner'] != null && 
          card['owner'] is String) {
        final owner = card['owner'] as String;
        apps[owner] = [...(apps[owner] ?? []), Map<String, dynamic>.from(card)];
      } else if (card is Map) {
        // Try to convert non-Map<String, dynamic> to proper format
        final Map<String, dynamic> convertedCard = Map<String, dynamic>.from(card);
        if (convertedCard['type'] == 'app' && 
            convertedCard['owner'] != null && 
            convertedCard['owner'] is String) {
          final owner = convertedCard['owner'] as String;
          apps[owner] = [...(apps[owner] ?? []), convertedCard];
        }
      }
    }
    return apps;
  }

  String get currentTurnUid => (currentTurn < playerOrder.length) ? playerOrder[currentTurn] : '';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameState &&
        other.status == status &&
        other.currentTurn == currentTurn &&
        other.winner == winner &&
        other.resignedBy == resignedBy &&
        _deepEquals(other.hands, hands) &&
        _deepEquals(other.burned, burned) &&
        _deepEquals(other.unused, unused) &&
        _deepEquals(other.appDeck, appDeck) &&
        _deepEquals(other.appPile, appPile) &&
        _deepEquals(other.pendingAttack, pendingAttack) &&
        _deepEquals(other.currentMessage, currentMessage);
  }

  @override
  int get hashCode => Object.hash(
    status,
    currentTurn,
    winner,
    resignedBy,
    Object.hashAll(burned),
    Object.hashAll(unused),
    Object.hashAll(appDeck),
    Object.hashAll(appPile),
  );

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == b) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (var key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return false;
  }
}

class GameTableScreen extends StatefulWidget {
  final String gameId;
  const GameTableScreen({Key? key, required this.gameId}) : super(key: key);

  @override
  State<GameTableScreen> createState() => _GameTableScreenState();
}

class _GameTableScreenState extends State<GameTableScreen> {
  bool _loading = false;
  String? _error;
  String? _visibleTurnMessage;
  DateTime? _visibleTurnMessageTs;
  GameState? _lastGameState;
  StreamSubscription<DatabaseEvent>? _gameSubscription;

  @override
  void initState() {
    super.initState();
    _setupGameStream();
  }

  @override
  void dispose() {
    _gameSubscription?.cancel();
    super.dispose();
  }

  void _setupGameStream() {
    final gameRef = FirebaseDatabase.instance.ref('games/${widget.gameId}');

    
    _gameSubscription = gameRef.onValue.listen((DatabaseEvent event) {
      try {
        if (event.snapshot.exists) {
          final gameValue = event.snapshot.value;
          if (gameValue != null) {
            final gameData = _safeMapConversion(gameValue);
            final newGameState = GameState.fromRealtimeDatabase(gameData);
            
            // Only update if there are actual changes
            if (_lastGameState != newGameState) {
              if (mounted) {
                setState(() {
                  _lastGameState = newGameState;
                });
                
                // Handle turn messages
                _processTurnMessage(newGameState);
              }
            }
          }
        } else {
          // Game was deleted or doesn't exist
          if (mounted) {
            setState(() {
              _error = 'Game not found or has been deleted';
            });
          }
        }
      } catch (e) {
        print('Error updating game state: $e');
        if (mounted) {
          setState(() {
            _error = 'Error loading game: ${e.toString()}';
          });
        }
      }
    }, onError: (error) {
      print('Game stream error: $error');
      if (mounted) {
        setState(() {
          _error = 'Connection error: ${error.toString()}';
        });
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

  void _processTurnMessage(GameState gameState) {
    final currentMessage = gameState.currentMessage;
    if (currentMessage != null) {
      final messageTs = currentMessage['ts'];
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (messageTs != null && messageTs is int && (now - messageTs) < 10000) {
        final playerNames = gameState.playerNames;
        String msg = '';
        final type = currentMessage['type'];
        
        if (type is String) {
          if (type == 'download_app') {
            final by = _getPlayerName(currentMessage['by'], playerNames);
            msg = '$by downloaded an App.';
          } else if (type == 'attack') {
            final by = _getPlayerName(currentMessage['by'], playerNames);
            final to = _getPlayerName(currentMessage['to'], playerNames);
            msg = '$by attacked $to.';
          } else if (type == 'defend') {
            final by = _getPlayerName(currentMessage['by'], playerNames);
            final attacker = _getPlayerName(currentMessage['attacker'], playerNames);
            msg = '$by defended against $attacker.';
          } else if (type == 'virus_return') {
            final attacker = _getPlayerName(currentMessage['attacker'], playerNames);
            final defender = _getPlayerName(currentMessage['defender'], playerNames);
            msg = '$attacker used Computer Virus on $defender.';
          } else if (type == 'hacker_theft') {
            final attacker = _getPlayerName(currentMessage['attacker'], playerNames);
            final defender = _getPlayerName(currentMessage['defender'], playerNames);
            msg = '$attacker stole an App from $defender.';
          } else if (type == 'discard') {
            final by = _getPlayerName(currentMessage['by'], playerNames);
            msg = '$by discarded a card.';
          }
        }
        
        if (msg.isNotEmpty) {
          setState(() {
            _visibleTurnMessage = msg;
            _visibleTurnMessageTs = DateTime.now();
          });
          
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && _visibleTurnMessageTs != null && 
                DateTime.now().difference(_visibleTurnMessageTs!) >= const Duration(seconds: 3)) {
              setState(() {
                _visibleTurnMessage = null;
              });
            }
          });
        }
      }
    }
  }

  String _getPlayerName(dynamic uid, Map<String, dynamic>? playerNames) {
    if (uid is String && playerNames != null && playerNames.containsKey(uid)) {
      final name = playerNames[uid];
      if (name is String) {
        return name;
      }
    }
    return 'Unknown Player';
  }

  Future<void> _playCard(int cardIdx, String cardType, {String? targetPlayerId}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('playCard');
      final data = <String, dynamic>{
        'gameId': widget.gameId,
        'cardType': cardType,
        'cardIdx': cardIdx,
      };
      
      // Only add targetPlayerId if it's not null and not empty
      if (targetPlayerId != null && targetPlayerId.isNotEmpty) {
        data['targetPlayerId'] = targetPlayerId;
      }
      
      final result = await callable.call(data);
      
      // Check if the result contains any error information
      if (result.data != null && result.data is Map) {
        final resultData = _safeMapConversion(result.data);
        if (resultData.containsKey('error')) {
          throw Exception(resultData['error']);
        }
      }
    } catch (e) {
      String errorMessage = 'An error occurred while playing the card.';
      
      if (e.toString().contains('Exception:')) {
        errorMessage = e.toString().split('Exception:')[1].trim();
      } else if (e.toString().contains('HttpsError:')) {
        // Handle Firebase Functions errors
        final errorStr = e.toString();
        if (errorStr.contains('not-found')) {
          errorMessage = 'Game not found.';
        } else if (errorStr.contains('failed-precondition')) {
          errorMessage = 'Invalid action. Please check the game state.';
        } else if (errorStr.contains('unauthenticated')) {
          errorMessage = 'Authentication required.';
        } else {
          errorMessage = 'Server error. Please try again.';
        }
      } else {
        errorMessage = e.toString();
      }
      
      setState(() { _error = errorMessage; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _discardCard(int cardIdx) async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseFunctions.instance.httpsCallable('discardCard').call({
        'gameId': widget.gameId,
        'cardIdx': cardIdx,
      });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _defend(int cardIdx, String cardType) async {
    setState(() { _loading = true; _error = null; });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('defend');
      final result = await callable.call({
        'gameId': widget.gameId,
        'cardType': cardType,
        'cardIdx': cardIdx,
      });
      
      // Check if the result contains any error information
      if (result.data != null && result.data is Map) {
        final resultData = _safeMapConversion(result.data);
        if (resultData.containsKey('error')) {
          throw Exception(resultData['error']);
        }
      }
    } catch (e) {
      String errorMessage = 'An error occurred while defending.';
      
      if (e.toString().contains('Exception:')) {
        errorMessage = e.toString().split('Exception:')[1].trim();
      } else if (e.toString().contains('HttpsError:')) {
        final errorStr = e.toString();
        if (errorStr.contains('not-found')) {
          errorMessage = 'Game not found.';
        } else if (errorStr.contains('failed-precondition')) {
          errorMessage = 'Invalid action. Please check the game state.';
        } else if (errorStr.contains('unauthenticated')) {
          errorMessage = 'Authentication required.';
        } else {
          errorMessage = 'Server error. Please try again.';
        }
      } else {
        errorMessage = e.toString();
      }
      
      setState(() { _error = errorMessage; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _submitToAttack() async {
    setState(() { _loading = true; _error = null; });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('submitToAttack');
      final result = await callable.call({
        'gameId': widget.gameId,
      });
      
      // Check if the result contains any error information
      if (result.data != null && result.data is Map) {
        final resultData = _safeMapConversion(result.data);
        if (resultData.containsKey('error')) {
          throw Exception(resultData['error']);
        }
      }
    } catch (e) {
      String errorMessage = 'An error occurred while submitting to attack.';
      
      if (e.toString().contains('Exception:')) {
        errorMessage = e.toString().split('Exception:')[1].trim();
      } else if (e.toString().contains('HttpsError:')) {
        final errorStr = e.toString();
        if (errorStr.contains('not-found')) {
          errorMessage = 'Game not found.';
        } else if (errorStr.contains('failed-precondition')) {
          errorMessage = 'Invalid action. Please check the game state.';
        } else if (errorStr.contains('unauthenticated')) {
          errorMessage = 'Authentication required.';
        } else {
          errorMessage = 'Server error. Please try again.';
        }
      } else {
        errorMessage = e.toString();
      }
      
      setState(() { _error = errorMessage; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _resign() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseFunctions.instance.httpsCallable('resign').call({
        'gameId': widget.gameId,
      });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _returnToLobby() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = "User is not authenticated.";
      });
      return;
    }
    try {
      print('Returning to lobby for game: ${widget.gameId}');
      
      // Call the Cloud Function to handle database updates atomically
      final callable = FirebaseFunctions.instance.httpsCallable('returnToLobby');
      final result = await callable.call({'gameId': widget.gameId});
      
      print('Return to lobby result: ${result.data}');
      
      // Add a small delay to ensure database update has propagated
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => LobbyScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      print('Error in _returnToLobby: ${e.toString()}');
      String errorMessage = 'Failed to return to lobby';
      
      if (e.toString().contains('Game not found')) {
        errorMessage = 'Game not found';
      } else if (e.toString().contains('unauthenticated')) {
        errorMessage = 'Please sign in to return to lobby';
      }
      
      setState(() {
        _error = errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return WillPopScope(
      onWillPop: () async {
        await _returnToLobby();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            'Matrix App Quest',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: ResponsiveLayout.getHeaderFontSize(context),
            ),
            textAlign: TextAlign.center,
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF232323),
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.info_outline,
              color: const Color(0xFF39FF14),
              size: ResponsiveLayout.getFontSize(context, baseSize: 24),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const GameRulesDialog(),
              );
            },
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: !_loading ? () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        backgroundColor: Colors.black,
                        title: const Text('Resign Game?', style: TextStyle(color: Color(0xFF39FF14))),
                        content: const Text(
                          'Are you sure you want to resign? This will end the game for all players.',
                          style: TextStyle(color: Colors.white),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Resign', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      );
                    },
                  );
                  if (confirmed == true) {
                    await _resign();
                  }
                } : null,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.12),
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.flag, size: 18, color: Colors.red),
                label: const Text(
                  'Resign',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _buildGameBody(user),
      ),
    );
  }

  Widget _buildGameBody(User? user) {
    if (_lastGameState == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00FF41),
        ),
      );
    }

    final gameState = _lastGameState!;

    // Handle finished game
    if (gameState.status == 'finished') {
      final winnerName = _getPlayerName(gameState.winner, gameState.playerNames);
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AnimatedWinDialog(
            winnerName: winnerName,
            gameId: widget.gameId,
            onReturnToLobby: _returnToLobby,
          ),
        ),
      );
    }

    // Handle resigned game
    if (gameState.status == 'resigned') {
      final resignedPlayerName = _getPlayerName(gameState.resignedBy, gameState.playerNames);
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AnimatedResignDialog(
            resignedPlayerName: resignedPlayerName,
            gameId: widget.gameId,
            onReturnToLobby: _returnToLobby,
          ),
        ),
      );
    }

    // Active game
    return _buildActiveGame(gameState, user);
  }

  Widget _buildActiveGame(GameState gameState, User? user) {
    final playerHand = user != null && gameState.hands[user.uid] != null 
        ? List<Map<String, dynamic>>.from(gameState.hands[user.uid]) 
        : <Map<String, dynamic>>[];

    final circleSize = ResponsiveLayout.getPlayerCircleSize(context);
    final spacing = ResponsiveLayout.getSpacing(context);
    final padding = ResponsiveLayout.getPadding(context);
    final cardWidth = ResponsiveLayout.getCardWidth(context);
    final cardHeight = ResponsiveLayout.getCardHeight(context);

    // Player position mapping
    List<String> positions = List.filled(4, '');
    if (user != null && gameState.playerOrder.length > 1) {
      final myIdx = gameState.playerOrder.indexOf(user.uid);
      for (int i = 0; i < gameState.playerOrder.length; i++) {
        int pos;
        if (i == myIdx) {
          pos = 1; // Bottom (self)
        } else if ((i - myIdx + gameState.playerOrder.length) % gameState.playerOrder.length == 1) {
          pos = 0; // Right (next)
        } else if ((i - myIdx + gameState.playerOrder.length) % gameState.playerOrder.length == 2) {
          pos = 3; // Top (opposite, only for 4 players)
        } else {
          pos = 2; // Left (previous)
        }
        positions[pos] = gameState.playerOrder[i];
      }
    }

    final rightUid = positions[0];
    final myUid = positions[1];
    final leftUid = positions[2];
    final topUid = positions[3];
    final rightName = rightUid.isNotEmpty ? _getPlayerName(rightUid, gameState.playerNames) : '';
    final myName = myUid.isNotEmpty ? _getPlayerName(myUid, gameState.playerNames) : '';
    final leftName = leftUid.isNotEmpty ? _getPlayerName(leftUid, gameState.playerNames) : '';
    final topName = topUid.isNotEmpty ? _getPlayerName(topUid, gameState.playerNames) : '';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Stack(
          children: [
            // Top player positioned at exact center X = w/2
            if (topName.isNotEmpty)
              Positioned(
                top: padding, // Added padding to match right player's padding
                left: 0,
                right: 0,
                child: Center(
                  child: _playerCircle(topName, isTurn: gameState.currentTurnUid == topUid, size: circleSize),
                ),
              ),
            
            // Main game content
            Column(
              children: [
                // Top section: Points table only
                Row(
                  children: [
                    // Points table in top left corner
                    _AnimatedNeonPointsTable(
                      key: ValueKey('points_${gameState.playerPoints.hashCode}'),
                      playerOrder: gameState.playerOrder,
                      playerNames: gameState.playerNames,
                      playerPoints: gameState.playerPoints,
                    ),
                    Spacer(), // Push points table to the left
                  ],
                ),
                
                SizedBox(height: spacing),
                
                // Turn message above card deck
                if (_visibleTurnMessage != null)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: spacing * 0.5),
                    child: AnimatedTurnSummaryOverlay(
                      key: ValueKey('turn_message_${_visibleTurnMessageTs?.millisecondsSinceEpoch}'),
                      message: _visibleTurnMessage!,
                    ),
                  ),
                
                // Middle section: Left player, piles, right player
                Expanded(
                  child: Row(
                    children: [
                      // Left player (centered vertically)
                      if (leftName.isNotEmpty)
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: _playerCircle(leftName, isTurn: gameState.currentTurnUid == leftUid, size: circleSize),
                          ),
                        ),
                      
                      // Center: Card piles
                      Expanded(
                        flex: 3,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // Limit pile size on desktop
                            final maxPileWidth = ResponsiveLayout.isDesktop(context) ? 80.0 : (constraints.maxWidth - 2 * spacing) / 3;
                            final pileCardWidth = (constraints.maxWidth - 2 * spacing) / 3;
                            final actualPileWidth = ResponsiveLayout.isDesktop(context) ? maxPileWidth : pileCardWidth;
                            final pileCardHeight = actualPileWidth * 1.4;
                            
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Pile labels - aligned with cards
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: actualPileWidth,
                                      child: _deckLabel('Burned'),
                                    ),
                                    SizedBox(width: spacing),
                                    SizedBox(
                                      width: actualPileWidth,
                                      child: _deckLabel('Unused'),
                                    ),
                                    SizedBox(width: spacing),
                                    SizedBox(
                                      width: actualPileWidth,
                                      child: _deckLabel('App'),
                                    ),
                                  ],
                                ),
                                SizedBox(height: spacing * 0.3),
                                // Pile cards
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _pileWidget(context, gameState.burned.length, actualPileWidth, pileCardHeight),
                                    SizedBox(width: spacing),
                                    _pileWidget(context, gameState.unused.length, actualPileWidth, pileCardHeight),
                                    SizedBox(width: spacing),
                                    _pileWidget(context, gameState.appDeck.length, actualPileWidth, pileCardHeight),
                                  ],
                                ),
                                SizedBox(height: spacing * 0.3),
                                // Pile counts - aligned with cards
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: actualPileWidth,
                                      child: _deckSize(gameState.burned.length, actualPileWidth),
                                    ),
                                    SizedBox(width: spacing),
                                    SizedBox(
                                      width: actualPileWidth,
                                      child: _deckSize(gameState.unused.length, actualPileWidth),
                                    ),
                                    SizedBox(width: spacing),
                                    SizedBox(
                                      width: actualPileWidth,
                                      child: _deckSize(gameState.appDeck.length, actualPileWidth),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      
                      // Right player (centered vertically)
                      if (rightName.isNotEmpty)
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: _playerCircle(rightName, isTurn: gameState.currentTurnUid == rightUid, size: circleSize),
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Bottom section: Collected apps, hand, and controls
                Column(
                  children: [
                    // User's collected app cards (horizontal scrollable)
                    if (user != null && gameState.playerApps[user.uid] != null && gameState.playerApps[user.uid]!.isNotEmpty)
                      Container(
                        height: ResponsiveLayout.isMobile(context) ? 60 : 80,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: gameState.playerApps[user.uid]!.map((card) => Container(
                              margin: EdgeInsets.symmetric(horizontal: spacing * 0.1),
                              child: _buildCompactAppCard(context, card),
                            )).toList(),
                          ),
                        ),
                      ),
                    
                    SizedBox(height: spacing * 0.5),
                    
                    // Player hand (horizontal scrollable with proper sizing)
                    if (myName.isNotEmpty)
                      Container(
                        height: cardHeight + spacing,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(playerHand.length, (idx) {
                              final card = playerHand[idx];
                              return Container(
                                margin: EdgeInsets.symmetric(horizontal: spacing * 0.1),
                                child: SizedBox(
                                  width: cardWidth,
                                  height: cardHeight,
                                  child: AnimatedHandCard(
                                    key: ValueKey('${card['type']}_${card['value'] ?? ''}_$idx'),
                                    card: card,
                                    canPlay: user != null && 
                                             gameState.currentTurnUid == user.uid && 
                                             !_loading && 
                                             gameState.pendingAttack == null,
                                    onTap: () async {
                                      final type = card['type'];
                                      if (type is String) {
                                        if (type == 'Download App') {
                                          await _playCard(idx, type);
                                        } else if (type == 'Computer Virus' || type == 'Hacker Theft') {
                                          final others = gameState.playerOrder.where((id) => user != null && id != user.uid && (gameState.playerApps[id]?.isNotEmpty ?? false)).toList();
                                          final target = await showDialog<String>(
                                            context: context,
                                            builder: (context) {
                                              return AlertDialog(
                                                backgroundColor: Colors.black,
                                                title: Text('Select target for $type', style: TextStyle(color: Color(0xFF39FF14), fontSize: ResponsiveLayout.getFontSize(context, baseSize: 16))),
                                                content: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    ...others.map((id) => ListTile(
                                                          title: Text(_getPlayerName(id, gameState.playerNames), style: TextStyle(color: Colors.white, fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14))),
                                                          onTap: () => Navigator.of(context).pop(id),
                                                        )),
                                                    SizedBox(height: spacing),
                                                    TextButton(
                                                      onPressed: () => Navigator.of(context).pop(),
                                                      child: Text('Cancel', style: TextStyle(color: Colors.white, fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14))),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          );
                                          if (target != null) {
                                            await _playCard(idx, type, targetPlayerId: target);
                                          }
                                        }
                                      }
                                    },
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    
                    // Action buttons and status
                    if (myName.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: spacing),
                        child: Column(
                          children: [
                            if (user != null && gameState.currentTurnUid == user.uid && !_loading && playerHand.isNotEmpty)
                              NeonButton(
                                onPressed: (gameState.pendingAttack != null && gameState.pendingAttack!['from'] == user.uid) 
                                    ? null
                                    : () async {
                                        final idx = await showDialog<int>(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              backgroundColor: Colors.black,
                                              title: Text('Select card to discard', style: TextStyle(color: Color(0xFF39FF14), fontSize: ResponsiveLayout.getFontSize(context, baseSize: 16))),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ...List.generate(playerHand.length, (i) => ListTile(
                                                        title: Text(
                                                          playerHand[i]['type'] == 'app'
                                                              ? 'App (${playerHand[i]['value'] ?? 0})'
                                                              : (playerHand[i]['type'] is String ? playerHand[i]['type'] as String : 'Unknown'),
                                                          style: TextStyle(color: Colors.white, fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14)),
                                                        ),
                                                        onTap: () => Navigator.of(context).pop(i),
                                                      )),
                                                  SizedBox(height: spacing),
                                                  TextButton(
                                                    onPressed: () => Navigator.of(context).pop(),
                                                    child: Text('Cancel', style: TextStyle(color: Colors.white, fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14))),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                        if (idx != null) {
                                          await _discardCard(idx);
                                        }
                                      },
                                child: Text(
                                  (gameState.pendingAttack != null && gameState.pendingAttack!['from'] == user.uid)
                                      ? 'Waiting for response...'
                                      : 'Pass turn & discard',
                                  style: TextStyle(fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12)),
                                ),
                              ),
                            if (_loading) 
                              Padding(
                                padding: EdgeInsets.only(top: spacing),
                                child: CircularProgressIndicator(color: Color(0xFF39FF14), strokeWidth: 2),
                              ),
                            if (_error != null) 
                              Padding(
                                padding: EdgeInsets.only(top: spacing * 0.5),
                                child: Text(
                                  _error!, 
                                  style: TextStyle(color: Colors.red, fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12)),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            
            // Overlays
            if (gameState.pendingAttack != null && gameState.pendingAttack!['to'] == user?.uid)
              Positioned.fill(
                child: _PendingAttackDialog(
                  attack: gameState.pendingAttack!,
                  hand: playerHand,
                  onDefend: (idx, type) => _defend(idx, type),
                  onSubmit: _submitToAttack,
                  loading: _loading,
                  playerNames: gameState.playerNames,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _deckLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: const Color(0xFF39FF14),
        fontSize: ResponsiveLayout.getFontSize(context, baseSize: 10),
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _deckSize(int count, double width) {
    return SizedBox(
      width: width,
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: ResponsiveLayout.getFontSize(context, baseSize: 10),
          fontWeight: FontWeight.bold,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _pileWidget(BuildContext context, int count, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF39FF14), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 2,
            spreadRadius: 1,
          ),
        ],
        image: DecorationImage(
          image: AssetImage('assets/card_back.jpeg'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _playerCircle(String name, {bool isTurn = false, bool isSelf = false, double? size}) {
    final darkGrey = const Color(0xFF232323);
    final neonGreen = const Color(0xFF00FF41);
    final circleSize = size ?? ResponsiveLayout.getPlayerCircleSize(context);
    return _AnimatedPlayerCircle(
      name: name,
      isTurn: isTurn,
      isSelf: isSelf,
      size: circleSize,
    );
  }
}

class _PendingAttackDialog extends StatelessWidget {
  final Map<String, dynamic> attack;
  final List<Map<String, dynamic>> hand;
  final Future<void> Function(int, String) onDefend;
  final Future<void> Function() onSubmit;
  final bool loading;
  final Map<String, dynamic>? playerNames;
  const _PendingAttackDialog({required this.attack, required this.hand, required this.onDefend, required this.onSubmit, required this.loading, required this.playerNames});

  @override
  Widget build(BuildContext context) {
    final attackType = attack['type'];
    final attacker = attack['from'];
    
    String attackerName = 'Unknown Player';
    if (attacker is String && playerNames != null && playerNames!.containsKey(attacker)) {
      final name = playerNames![attacker];
      if (name is String) {
        attackerName = name;
      }
    }
    
    final canDefend = hand.indexWhere((c) => 
      (attackType == 'Computer Virus' && c['type'] is String && c['type'] == 'Firewall') || 
      (attackType == 'Hacker Theft' && c['type'] is String && c['type'] == 'IT Guy')) != -1;
    final defendIdx = hand.indexWhere((c) => 
      (attackType == 'Computer Virus' && c['type'] is String && c['type'] == 'Firewall') || 
      (attackType == 'Hacker Theft' && c['type'] is String && c['type'] == 'IT Guy'));
    final defendType = defendIdx != -1 && hand[defendIdx]['type'] is String ? hand[defendIdx]['type'] as String : null;
    
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF39FF14), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF39FF14).withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$attackerName used $attackType on you!',
                style: const TextStyle(color: Color(0xFF39FF14), fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              if (canDefend)
                NeonButton(
                  onPressed: !loading && canDefend ? () => onDefend(defendIdx, defendType!) : null,
                  child: Text('Defend (${defendType ?? ''})'),
                ),
              NeonButton(
                onPressed: !loading ? onSubmit : null,
                child: Text(canDefend ? 'Submit (don\'t defend)' : 'Submit'),
              ),
              if (loading) const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: CircularProgressIndicator(color: Color(0xFF39FF14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnimatedHand extends StatefulWidget {
  final List<Map<String, dynamic>> cards;
  final bool canPlay;
  final void Function(int, Map<String, dynamic>) onPlay;
  const AnimatedHand({Key? key, required this.cards, required this.canPlay, required this.onPlay}) : super(key: key);

  @override
  State<AnimatedHand> createState() => _AnimatedHandState();
}

class _AnimatedHandState extends State<AnimatedHand> {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.cards.length, (idx) {
        final card = widget.cards[idx];
        return AnimatedHandCard(
          key: ValueKey('${card['type']}_${card['value'] ?? ''}_$idx'),
          card: card,
          canPlay: widget.canPlay,
          onTap: () => widget.onPlay(idx, card),
        );
      }),
    );
  }
}

class AnimatedHandCard extends StatefulWidget {
  final Map<String, dynamic> card;
  final bool canPlay;
  final VoidCallback onTap;
  const AnimatedHandCard({
    Key? key, 
    required this.card, 
    required this.canPlay, 
    required this.onTap,
  }) : super(key: key);

  @override
  State<AnimatedHandCard> createState() => _AnimatedHandCardState();
}

class _AnimatedHandCardState extends State<AnimatedHandCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.canPlay ? () {
        _controller.forward().then((_) => _controller.reverse());
        widget.onTap();
      } : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: _cardContent(),
          );
        },
      ),
    );
  }

  Widget _cardContent() {
    final cardWidth = ResponsiveLayout.getCardWidth(context);
    final cardHeight = ResponsiveLayout.getCardHeight(context);
    return _buildCard(context, widget.card, cardWidth, cardHeight);
  }
}

class AnimatedTurnSummaryOverlay extends StatefulWidget {
  final String message;
  const AnimatedTurnSummaryOverlay({Key? key, required this.message}) : super(key: key);

  @override
  State<AnimatedTurnSummaryOverlay> createState() => _AnimatedTurnSummaryOverlayState();
}

class _AnimatedTurnSummaryOverlayState extends State<AnimatedTurnSummaryOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _slide = Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _opacity,
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: ResponsiveLayout.isMobile(context) ? 280 : 340,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveLayout.isMobile(context) ? 16 : 22,
              vertical: ResponsiveLayout.isMobile(context) ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.97),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFF00FF41), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FF41).withOpacity(0.18),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Text(
              widget.message,
              style: TextStyle(
                color: Color(0xFF39FF14),
                fontWeight: FontWeight.bold,
                fontSize: ResponsiveLayout.isMobile(context) 
                    ? ResponsiveLayout.getFontSize(context, baseSize: 14)
                    : 17,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class NeonButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color color;
  final Color textColor;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final double borderRadius;
  final bool enabled;
  const NeonButton({
    Key? key,
    required this.onPressed,
    required this.child,
    this.color = const Color(0xFF00FF41),
    this.textColor = Colors.black,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    this.fontSize = 18,
    this.borderRadius = 12,
    this.enabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(
          color: enabled ? color : color.withOpacity(0.5),
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.7),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: color, width: 2),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: fontSize,
            shadows: [
              Shadow(color: color.withOpacity(0.7), blurRadius: 8),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class AnimatedWinDialog extends StatefulWidget {
  final String winnerName;
  final String gameId;
  final VoidCallback onReturnToLobby;

  const AnimatedWinDialog({
    Key? key,
    required this.winnerName,
    required this.gameId,
    required this.onReturnToLobby,
  }) : super(key: key);

  @override
  State<AnimatedWinDialog> createState() => _AnimatedWinDialogState();
}

class _AnimatedWinDialogState extends State<AnimatedWinDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back navigation
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: FadeTransition(
            opacity: _opacity,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 350),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.98),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Color(0xFF00FF41), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF41).withOpacity(0.25),
                    blurRadius: 32,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events, color: Color(0xFF00FF41), size: 48),
                  const SizedBox(height: 10),
                  Text(
                    'Game Over!',
                    style: const TextStyle(
                      color: Color(0xFF00FF41),
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.winnerName} has conquered the Matrix and claimed ultimate victory!\nWOO HOO! 🎉',
                    style: const TextStyle(
                      color: Color(0xFF39FF14),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  NeonButton(
                    onPressed: widget.onReturnToLobby,
                    child: const Text('Return to Lobby'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedResignDialog extends StatefulWidget {
  final String resignedPlayerName;
  final String gameId;
  final VoidCallback onReturnToLobby;

  const AnimatedResignDialog({
    Key? key,
    required this.resignedPlayerName,
    required this.gameId,
    required this.onReturnToLobby,
  }) : super(key: key);

  @override
  State<AnimatedResignDialog> createState() => _AnimatedResignDialogState();
}

class _AnimatedResignDialogState extends State<AnimatedResignDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back navigation
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: FadeTransition(
            opacity: _opacity,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 350),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.98),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Color(0xFF00FF41), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF41).withOpacity(0.25),
                    blurRadius: 32,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🏳️',
                    style: TextStyle(fontSize: 48),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Game Over!',
                    style: const TextStyle(
                      color: Color(0xFF00FF41),
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.resignedPlayerName} resigned the game.',
                    style: const TextStyle(
                      color: Color(0xFF39FF14),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  NeonButton(
                    onPressed: widget.onReturnToLobby,
                    child: const Text('Return to Lobby'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedNeonPointsTable extends StatefulWidget {
  final List playerOrder;
  final Map<String, dynamic>? playerNames;
  final Map playerPoints;
  const _AnimatedNeonPointsTable({Key? key, required this.playerOrder, required this.playerNames, required this.playerPoints}) : super(key: key);

  @override
  State<_AnimatedNeonPointsTable> createState() => _AnimatedNeonPointsTableState();
}

class _AnimatedNeonPointsTableState extends State<_AnimatedNeonPointsTable> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _borderColor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _borderColor = ColorTween(
      begin: const Color(0xFF00FF41),
      end: const Color(0xFF39FF14),
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Text(
            'SCORE',
            style: TextStyle(
              color: const Color(0xFF00FF41),
              fontWeight: FontWeight.bold,
              fontSize: ResponsiveLayout.getFontSize(context, baseSize: 15),
              letterSpacing: 1.3,
            ),
          ),
        ),
        ...widget.playerOrder.map((uid) {
          final playerName = widget.playerNames != null && widget.playerNames!.containsKey(uid)
              ? widget.playerNames![uid] ?? 'Unknown'
              : 'Unknown';
          final points = widget.playerPoints[uid] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: ResponsiveLayout.isMobile(context) ? 80 : 110,
                  child: Text(
                    playerName,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: ResponsiveLayout.getFontSize(context, baseSize: 14),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 14),
                Text(
                  points.toString(),
                  style: TextStyle(
                    color: const Color(0xFF00FF41),
                    fontWeight: FontWeight.bold,
                    fontSize: ResponsiveLayout.isMobile(context) 
                        ? ResponsiveLayout.getFontSize(context, baseSize: 18)
                        : ResponsiveLayout.getFontSize(context, baseSize: 22),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}

class AnimatedCount extends ImplicitlyAnimatedWidget {
  final int value;
  final TextStyle? style;
  const AnimatedCount({Key? key, required this.value, Duration duration = const Duration(milliseconds: 500), this.style}) : super(key: key, duration: duration);

  @override
  AnimatedWidgetBaseState<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends AnimatedWidgetBaseState<AnimatedCount> {
  IntTween? _intTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _intTween = visitor(
      _intTween,
      widget.value,
      (dynamic value) => IntTween(begin: value as int),
    ) as IntTween?;
  }

  @override
  Widget build(BuildContext context) {
    return Text('${_intTween?.evaluate(animation) ?? widget.value}', style: widget.style);
  }
}

class _AnimatedPlayerCircle extends StatelessWidget {
  final String name;
  final bool isTurn;
  final bool isSelf;
  final double size;
  const _AnimatedPlayerCircle({required this.name, this.isTurn = false, this.isSelf = false, required this.size});

  @override
  Widget build(BuildContext context) {
    final darkGrey = const Color(0xFF232323);
    final neonGreen = const Color(0xFF00FF41);
    return Container(
      decoration: isTurn
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: neonGreen.withOpacity(0.8),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: neonGreen.withOpacity(0.5),
                  blurRadius: 32,
                  spreadRadius: 8,
                ),
              ],
            )
          : BoxDecoration(
              shape: BoxShape.circle,
              color: darkGrey.withOpacity(0.12),
              boxShadow: [
                BoxShadow(
                  color: darkGrey.withOpacity(0.18),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: isSelf ? Colors.blue : darkGrey,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(
              name,
              style: TextStyle(
                color: Colors.white,
                fontSize: ResponsiveLayout.getFontSize(context, baseSize: 12),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

String _getCardAsset(String type) {
  String asset = 'assets/card_back.jpeg';
  if (type == 'Download App') asset = 'assets/downloadapp.jpeg';
  else if (type == 'Computer Virus') asset = 'assets/virus.jpeg';
  else if (type == 'Firewall') asset = 'assets/firewall.jpeg';
  else if (type == 'IT Guy') asset = 'assets/itguy.jpeg';
  else if (type == 'Hacker Theft') asset = 'assets/hacker.jpeg';
  return asset;
}

String _getAppLogoAsset(int value) {
  switch (value) {
    case 4:
      return 'assets/apps/youtube.jpeg';
    case 3:
      return 'assets/apps/chrome.jpeg';
    case 2:
      return 'assets/apps/instagram.jpeg';
    case 1:
      return 'assets/apps/tiktok.jpeg';
    default:
      return 'assets/card_back.jpeg';
  }
}

Widget _buildCard(BuildContext context, Map<String, dynamic> card, double width, double height) {
  final type = (card['type'] is String) ? card['type'] as String : 'Unknown';
  final value = (card['value'] is int) ? card['value'] as int : null;
  
  // Special handling for app cards
  if (type == 'app' && value != null) {
    final appLogoAsset = _getAppLogoAsset(value);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF39FF14), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 2,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // App logo
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(5),
                ),
                image: DecorationImage(
                  image: AssetImage(appLogoAsset),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // Points display
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(5),
                  bottomRight: Radius.circular(5),
                ),
              ),
              child: Center(
                child: Text(
                  '$value',
                  style: TextStyle(
                    color: const Color(0xFF39FF14),
                    fontWeight: FontWeight.bold,
                    fontSize: ResponsiveLayout.isMobile(context) 
                        ? ResponsiveLayout.getFontSize(context, baseSize: 12)
                        : ResponsiveLayout.getFontSize(context, baseSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Regular cards (non-app cards)
  final asset = _getCardAsset(type);
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFF39FF14), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.green.withOpacity(0.1),
          blurRadius: 2,
          spreadRadius: 1,
        ),
      ],
      image: DecorationImage(
        image: AssetImage(asset),
        fit: BoxFit.cover,
      ),
    ),
  );
}

Widget _buildCompactAppCard(BuildContext context, Map<String, dynamic> card) {
  final type = (card['type'] is String) ? card['type'] as String : 'Unknown';
  final value = (card['value'] is int) ? card['value'] as int : null;
  
  // Special handling for app cards
  if (type == 'app' && value != null) {
    final appLogoAsset = _getAppLogoAsset(value);
    return Container(
      width: ResponsiveLayout.isMobile(context) ? 50 : 60,
      height: ResponsiveLayout.isMobile(context) ? 50 : 60,
      child: Stack(
        children: [
          // App logo
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              image: DecorationImage(
                image: AssetImage(appLogoAsset),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Points display overlay
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(2),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                '$value',
                style: TextStyle(
                  color: const Color(0xFF39FF14),
                  fontWeight: FontWeight.bold,
                  fontSize: ResponsiveLayout.isMobile(context) 
                      ? ResponsiveLayout.getFontSize(context, baseSize: 12)
                      : ResponsiveLayout.getFontSize(context, baseSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Regular cards (non-app cards) - shouldn't appear here but just in case
  final asset = _getCardAsset(type);
  return Container(
    width: ResponsiveLayout.isMobile(context) ? 50 : 60,
    height: ResponsiveLayout.isMobile(context) ? 50 : 60,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      image: DecorationImage(
        image: AssetImage(asset),
        fit: BoxFit.cover,
      ),
    ),
  );
}

