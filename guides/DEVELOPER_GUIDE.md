# App Quest - Developer's Guide

## High-Level Architecture

App Quest is a real-time multiplayer card game built with a **Flutter frontend** and **Firebase backend**. The architecture follows a client-server model with real-time synchronization.

### System Components

1. **Frontend**: Flutter app with responsive UI for web and mobile
2. **Backend**: Firebase Cloud Functions handling game logic and state management
3. **Database**: Hybrid approach using both Realtime Database and Firestore
4. **Authentication**: Firebase Auth with Google Sign-In

## Database Design

### Realtime Database (Real-time game data)

- **`/games/{gameId}`**: Active game states, player actions, card states
- **`/lobbies/{lobbyId}`**: Lobby information, player lists, game setup
- **`/onlineUsers/{userId}`**: Active player status and presence

### Firestore (Persistent data)

- **`scores` collection**: Player statistics and game history

## 🏗️ Project Structure

```
MatrixAppQuest-Project/
├── frontend/                          # Flutter app
│   ├── lib/
│   │   ├── main.dart                  # App entry point & auth
│   │   └── screens/
│   │       ├── login_screen.dart
│   │       ├── lobby_screen.dart
│   │       └── game_table_screen.dart
│   └── assets/                        # Game images and fonts
├── backend/                           # Firebase backend
│   ├── functions/
│   │   └── index.js                   # Backend game logic
│   ├── firebase.json                  # Firebase configuration
│   └── database.rules.json            # Security rules
├── guides/
│   ├── USER_GUIDE.md
│   └── DEVELOPER_GUIDE.md
└── README.md
```

## Main Modules

### Frontend Modules

#### 1. Authentication System (`main.dart`)

- **Purpose**: Handles user login/logout and app initialization
- **Key Components**:
  - `MyApp`: Main app widget with theme configuration
  - `AuthGate`: Authentication state management
  - Firebase Auth integration with Google Sign-In
- **Interactions**: Connects to Firebase Auth, manages user sessions

#### 2. Lobby Management (`lobby_screen.dart`)

- **Purpose**: Creating/joining game lobbies, player matchmaking
- **Key Components**:
  - `LobbyScreen`: Main lobby interface
  - `WaitingScreen`: Waiting room for players
  - `LobbyData`: Data model for lobby information
- **Interactions**:
  - Real-time listeners to `/lobbies` in Realtime Database
  - Calls Cloud Functions: `createLobby`, `joinLobby`, `leaveLobby`

#### 3. Game Interface (`game_table_screen.dart`)

- **Purpose**: Main gameplay UI, card management, player actions
- **Key Components**:
  - `GameTableScreen`: Game board and player interface
  - `GameState`: Game state data model
  - Card rendering and interaction handlers
- **Interactions**:
  - Real-time listeners to `/games/{gameId}` in Realtime Database
  - Calls Cloud Functions: `playCard`, `discardCard`, `defend`, `submitToAttack`

### Backend Modules

#### 1. Game Logic (`functions/index.js`)

- **Purpose**: Serverless functions handling all game mechanics
- **Key Functions**:
  - **Lobby Management**: `createLobby`, `joinLobby`, `leaveLobby`, `cancelLobby`
  - **Game Actions**: `playCard`, `discardCard`, `defend`, `submitToAttack`
  - **Game Flow**: `onLobbyFilled` (auto-start games), `resign`
  - **User Management**: `updateUserOnlineStatus`, `removeUserOnlineStatus`
- **Interactions**:
  - Reads/writes to Realtime Database for game state
  - Uses Firestore for persistent scores
  - Triggers on database changes

## Component Interactions

### 1. Game Start Flow

```
User creates lobby → Cloud Function creates `/lobbies/{id}` →
Other players join → `onLobbyFilled` trigger →
Game created in `/games/{id}` → Players redirected to game
```

### 2. Gameplay Flow

```
Player action in UI → Cloud Function called →
Game state updated in Realtime DB →
All players receive real-time updates → UI updates
```

### 3. Real-time Synchronization

- **Frontend**: Uses `onValue` listeners for real-time data
- **Backend**: Uses `onValueWritten` triggers for automatic responses
- **Database**: Realtime Database provides instant synchronization

## Development Tools & Libraries

### Frontend Dependencies

```yaml
# Core Flutter/Firebase
flutter_sdk
firebase_core: ^3.5.0
firebase_auth: ^5.2.1
firebase_database: ^11.1.0
cloud_firestore: ^5.4.1
cloud_functions: ^5.1.0

# UI/Utilities
http: ^1.1.0              # HTTP requests
```

### Backend Dependencies

```json
{
  "firebase-admin": "^12.0.0",
  "firebase-functions": "^5.0.0"
}
```

### Development Tools

- **Flutter SDK**: Cross-platform app development
- **Firebase CLI**: Project deployment and management
- **Node.js**: Backend function development
- **VS Code/Android Studio**: IDE with Flutter extensions

## Key Design Decisions

### 1. Hybrid Database Approach

- **Realtime Database**: Used for frequently changing game data requiring instant sync
- **Firestore**: Used for persistent data with complex queries (scores)
- **Benefit**: Optimized performance for real-time gaming

### 2. Serverless Architecture

- **Cloud Functions**: Handle all game logic server-side
- **Benefit**: Prevents cheating, ensures fair gameplay, automatic scaling

### 3. State Management

- **Frontend**: Stream-based reactive UI updates
- **Backend**: Transactional database operations
- **Benefit**: Consistent game state across all players

## Development Workflow

### 1. Local Development

```bash
# Start Firebase emulators
firebase emulators:start

# Run Flutter app
cd frontend
flutter run -d web
```

### 2. Testing

```bash
# Run Flutter tests
cd frontend
flutter test

# Deploy to staging
firebase deploy --only functions,database
```

### 3. Production Deployment

```bash
# Deploy everything
firebase deploy

# Deploy specific services
firebase deploy --only hosting,functions,database
```

## Security Model

### Authentication

- Google Sign-In required for all users
- Firebase Auth tokens validate all requests

### Database Rules

- All data requires authentication
- Game/lobby access restricted to participants
- Server-side validation in Cloud Functions

## Performance Considerations

### Real-time Updates

- Use targeted database listeners (specific game/lobby IDs)
- Automatic cleanup of inactive games/lobbies
- Efficient data structures for quick lookups

### Scalability

- Serverless functions scale automatically
- Database indexing for common queries
- Optimized Flutter widgets for smooth animations

## Common Development Tasks

### Adding New Card Types

1. Update game rules specification
2. Add card logic in Cloud Functions
3. Update UI components in Flutter
4. Add new card assets

### Modifying Game Rules

1. Update `functions/index.js` game logic
2. Update frontend validation
3. Deploy functions: `firebase deploy --only functions`

### Adding New Screens

1. Create new screen in `frontend/lib/screens/`
2. Add routing in `main.dart`
3. Update navigation flows
