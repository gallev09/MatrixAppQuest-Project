# App Quest - User Guide

## Overview

App Quest is a multiplayer card game with a Matrix theme where 2-4 players compete to collect "App" cards and reach 7 points to win. Players use special cards like Hacker Theft, Computer Virus, and IT Guy to attack and defend against opponents.

## Prerequisites

- **Node.js** (version 16 or higher) - [Download here](https://nodejs.org/)
- **Flutter SDK** (version 3.0 or higher) - [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Firebase CLI** - Install with: `npm install -g firebase-tools`
- **Git** - [Download here](https://git-scm.com/downloads)

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/gallev09/MatrixAppQuest-Project.git
cd MatrixAppQuest-Project
```

### 2. Install Flutter Dependencies

```bash
cd frontend
flutter pub get
cd ..
```

### 3. Install Firebase Function Dependencies

```bash
cd functions
npm install
cd ..
```

## Firebase Configuration

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use existing one
3. Enable the following services:
   - **Authentication** (with Google Sign-In)
   - **Cloud Functions**
   - **Firestore Database**
   - **Realtime Database**

### 2. Configure Firebase

1. Login to Firebase: `firebase login`
2. Set your project: `firebase use <your-project-id>`
3. Update `frontend/lib/firebase_options.dart` with your Firebase configuration

### 3. Set Up Databases

1. **Realtime Database**: Create database at `https://your-project-id.firebaseio.com/`
2. **Firestore**: Create database in your preferred region
3. The database rules will be deployed automatically

## Deployment

### 1. Deploy Backend Services

```bash
# Deploy Cloud Functions and database rules
firebase deploy --only functions,database
```

### 2. Deploy Frontend

Choose your platform:

**For Web:**

```bash
cd frontend
flutter build web
firebase deploy --only hosting
```

**For Mobile (Development):**

```bash
cd frontend
flutter build web
```

## Running the Game

### 1. Access the Game

- **Web**: Visit your Firebase hosting URL or `localhost:5000` for local testing
- **Mobile**: Launch the installed app

### 2. Sign In

- Use your Google account to sign in
- The app will automatically create your player profile

### 3. Play the Game

1. **Create/Join Lobby**: Start a new game or join an existing lobby
2. **Wait for Players**: Game starts when 2-4 players join
3. **Play Cards**: Use your cards strategically to collect App cards
4. **Win**: First player to reach 7 points wins!

## Game Rules Quick Reference

- **Goal**: Collect App cards worth 7 points total
- **Hand Size**: Always maintain 3 non-App cards
- **Card Types**:
  - App cards (1-4 points each)
  - Download App (draw App card)
  - Computer Virus (attack opponents)
  - Hacker Theft (steal App cards)
  - IT Guy (defend against attacks)
  - Firewall (protect against theft)

## Troubleshooting

### Common Issues

1. **"Permission denied" errors**: Check Firebase security rules deployment
2. **"Game not found" errors**: Ensure Realtime Database is enabled
3. **Authentication issues**: Verify Google Sign-In is configured in Firebase Console
4. **Slow updates**: Check internet connection and Firebase region settings

### Getting Help

- Check the browser console for error messages
- Verify Firebase project configuration
- Ensure all dependencies are installed correctly

## System Requirements

- **Web**: Modern browser with JavaScript enabled
