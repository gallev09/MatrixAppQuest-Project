const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { onCall: httpsOnCall } = require("firebase-functions/v2/https");
const { onValueWritten } = require("firebase-functions/v2/database");

admin.initializeApp({
  databaseURL: "https://newversion-cardgame-2025.firebaseio.com/",
});

const rtdb = admin.database();
const db = admin.firestore();

// Helper functions
function getNextTurn(game) {
  return (game.currentTurn + 1) % game.playerOrder.length;
}

function checkWin(game) {
  const appPile = game.appPile || [];
  const points = {};
  for (const pid of game.playerOrder) points[pid] = 0;

  // Debug: Log the appPile to see what's happening
  console.log("CheckWin - appPile:", JSON.stringify(appPile, null, 2));

  for (const card of appPile) {
    if (card.owner && points[card.owner] !== undefined) {
      // Ensure card value is within valid range (1-4)
      const cardValue = Math.max(0, Math.min(4, card.value || 0));
      points[card.owner] += cardValue;

      // Debug: Log each card's contribution
      console.log(
        `Player ${card.owner} gets ${cardValue} points from card:`,
        card
      );
    }
  }

  // Debug: Log final points
  console.log("Final points:", points);

  for (const pid in points) {
    if (points[pid] >= 7) {
      console.log(`Player ${pid} wins with ${points[pid]} points!`);
      return pid;
    }
  }
  return null;
}

function drawToThree(hand, unused) {
  hand = hand.filter((c) => c.type !== "app");
  while (hand.length < 3 && unused.length > 0) {
    const next = unused.pop();
    if (next.type !== "app") hand.push(next);
  }
  return [hand, unused];
}

function shuffle(array) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}

// Play a card
exports.playCard = httpsOnCall(async (req) => {
  const { gameId, cardType, cardIdx, targetPlayerId } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!gameId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Game ID required"
    );

  const gameRef = rtdb.ref(`games/${gameId}`);
  const gameSnapshot = await gameRef.once("value");
  const game = gameSnapshot.val();
  if (!game)
    throw new functions.https.HttpsError("not-found", "Game not found");

  let hands = { ...game.hands };
  let hand = hands[uid] || [];
  let unused = [...(game.unused || [])];
  let burned = [...(game.burned || [])];
  let appDeck = [...(game.appDeck || [])];
  let appPile = [...(game.appPile || [])];

  // Auto draw at start of turn
  if (!game.lastDrawTurn || game.lastDrawTurn[uid] !== game.currentTurn) {
    if (unused.length > 0) {
      const next = unused.pop();
      if (next.type !== "app") hand.push(next);
    }
  }

  const playedCard = hand[cardIdx];
  hand = hand.filter((_, i) => i !== cardIdx);

  if (cardType === "Download App") {
    if (appDeck.length === 0)
      throw new functions.https.HttpsError(
        "failed-precondition",
        "No app cards left"
      );
    const appCard = appDeck.pop();

    // Validate the app card has a proper value (1-4)
    if (!appCard.value || appCard.value < 1 || appCard.value > 4) {
      console.error("Invalid app card value:", appCard);
      throw new functions.https.HttpsError(
        "internal",
        "Invalid app card value"
      );
    }

    appCard.owner = uid;
    appPile.push(appCard);
    burned.push(playedCard);
    [hand, unused] = drawToThree(hand, unused);
    const nextTurn = getNextTurn(game);

    // Debug: Log the card that was drawn
    console.log(`Player ${uid} drew app card:`, appCard);

    const winner = checkWin({ ...game, appPile });

    const gameUpdate = {
      ...game,
      hands: { ...hands, [uid]: hand },
      burned,
      appDeck,
      appPile,
      unused,
      currentTurn: nextTurn,
      lastDrawTurn: { ...(game.lastDrawTurn || {}), [uid]: nextTurn },
      currentMessage: {
        type: "download_app",
        by: uid,
        card: appCard,
        ts: Date.now(),
      },
    };

    if (winner) {
      gameUpdate.status = "finished";
      gameUpdate.winner = winner;

      // Update winner's score in Firestore leaderboard
      try {
        const winnerName = game.playerNames[winner] || "Unknown Player";
        const scoreRef = db.collection("scores").doc(winner);

        await db.runTransaction(async (tx) => {
          const scoreDoc = await tx.get(scoreRef);

          if (scoreDoc.exists) {
            const currentWins = scoreDoc.data().wins || 0;
            tx.update(scoreRef, {
              wins: currentWins + 1,
              playerName: winnerName,
            });
          } else {
            tx.set(scoreRef, {
              uid: winner,
              playerName: winnerName,
              wins: 1,
            });
          }
        });

        console.log(
          `Updated leaderboard for winner: ${winnerName} (${winner})`
        );
      } catch (error) {
        console.error("Error updating winner's score:", error);
        // Don't fail the game update if leaderboard update fails
      }
    }

    await gameRef.set(gameUpdate);
    return { success: true };
  }

  // Attack cards
  [hand, unused] = drawToThree(hand, unused);
  await gameRef.set({
    ...game,
    hands: { ...hands, [uid]: hand },
    burned,
    appDeck,
    appPile,
    unused,
    pendingAttack: {
      type: cardType,
      from: uid,
      to: targetPlayerId,
      card: playedCard,
    },
    currentMessage: {
      type: "attack",
      by: uid,
      card: playedCard,
      to: targetPlayerId,
      ts: Date.now(),
    },
  });

  return { success: true };
});

// Discard a card
exports.discardCard = httpsOnCall(async (req) => {
  const { gameId, cardIdx } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!gameId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Game ID required"
    );

  const gameRef = rtdb.ref(`games/${gameId}`);
  const gameSnapshot = await gameRef.once("value");
  const game = gameSnapshot.val();
  if (!game)
    throw new functions.https.HttpsError("not-found", "Game not found");

  let hands = { ...game.hands };
  let hand = hands[uid] || [];
  let unused = [...(game.unused || [])];
  let burned = [...(game.burned || [])];

  // Auto draw at start of turn
  if (!game.lastDrawTurn || game.lastDrawTurn[uid] !== game.currentTurn) {
    if (unused.length > 0) {
      const next = unused.pop();
      if (next.type !== "app") hand.push(next);
    }
  }

  const discardedCard = hand[cardIdx];
  hand = hand.filter((_, i) => i !== cardIdx);
  burned.push(discardedCard);
  [hand, unused] = drawToThree(hand, unused);
  const nextTurn = getNextTurn(game);

  await gameRef.set({
    ...game,
    hands: { ...hands, [uid]: hand },
    burned,
    unused,
    currentTurn: nextTurn,
    lastDrawTurn: { ...(game.lastDrawTurn || {}), [uid]: nextTurn },
    currentMessage: {
      type: "discard",
      by: uid,
      card: discardedCard,
      ts: Date.now(),
    },
  });

  return { success: true };
});

// Defend against attack
exports.defend = httpsOnCall(async (req) => {
  const { gameId, cardType, cardIdx } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!gameId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Game ID required"
    );

  const gameRef = rtdb.ref(`games/${gameId}`);
  const gameSnapshot = await gameRef.once("value");
  const game = gameSnapshot.val();
  if (!game)
    throw new functions.https.HttpsError("not-found", "Game not found");

  let hands = { ...game.hands };
  let hand = hands[uid] || [];
  let unused = [...(game.unused || [])];
  let burned = [...(game.burned || [])];

  // Add attack card and defense card to burned
  burned.push(game.pendingAttack.card);
  burned.push(hand[cardIdx]);
  hand = hand.filter((_, i) => i !== cardIdx);

  [hand, unused] = drawToThree(hand, unused);
  const nextTurn = getNextTurn(game);

  await gameRef.set({
    ...game,
    hands: { ...hands, [uid]: hand },
    burned,
    unused,
    pendingAttack: null,
    currentTurn: nextTurn,
    lastDrawTurn: { ...(game.lastDrawTurn || {}), [uid]: nextTurn },
    currentMessage: {
      type: "defend",
      by: uid,
      attacker: game.pendingAttack.from, // ← Add attacker ID
      card: cardType,
      ts: Date.now(),
    },
  });

  return { success: true };
});

// Submit to attack
exports.submitToAttack = httpsOnCall(async (req) => {
  const { gameId } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!gameId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Game ID required"
    );

  const gameRef = rtdb.ref(`games/${gameId}`);
  const gameSnapshot = await gameRef.once("value");
  const game = gameSnapshot.val();
  if (!game)
    throw new functions.https.HttpsError("not-found", "Game not found");

  let hands = { ...game.hands };
  let unused = [...(game.unused || [])];
  let burned = [...(game.burned || [])];
  let appDeck = [...(game.appDeck || [])];
  let appPile = [...(game.appPile || [])];

  const pending = game.pendingAttack;
  burned.push(pending.card);

  // Determine what type of attack effect message to show
  let messageType = "submit_attack";
  let messageData = {
    type: messageType,
    by: uid,
    ts: Date.now(),
  };

  // Apply attack effect and set specific message
  if (pending.type === "Computer Virus") {
    const myApps = appPile.filter((c) => c.owner === uid);
    if (myApps.length > 0) {
      const idx = Math.floor(Math.random() * myApps.length);
      appPile = appPile.filter((c) => {
        if (
          c.owner === uid &&
          c.type === "app" &&
          c.value === myApps[idx].value
        ) {
          c.owner = null;
          appDeck.push(c);
          return false;
        }
        return true;
      });
      appDeck = shuffle(appDeck);

      // Set virus-specific message
      messageData = {
        type: "virus_return",
        attacker: pending.from,
        defender: uid,
        ts: Date.now(),
      };
    }
  }

  if (pending.type === "Hacker Theft") {
    const myApps = appPile.filter((c) => c.owner === uid);
    if (myApps.length > 0) {
      const idx = Math.floor(Math.random() * myApps.length);
      appPile = appPile.map((c) => {
        if (
          c.owner === uid &&
          c.type === "app" &&
          c.value === myApps[idx].value
        ) {
          return { ...c, owner: pending.from };
        }
        return c;
      });

      // Set hacker-specific message
      messageData = {
        type: "hacker_theft",
        attacker: pending.from,
        defender: uid,
        ts: Date.now(),
      };
    }
  }

  let hand = hands[uid] || [];
  [hand, unused] = drawToThree(hand, unused);
  const nextTurn = getNextTurn(game);
  const winner = checkWin({ ...game, appPile });

  const gameUpdate = {
    ...game,
    hands: { ...hands, [uid]: hand },
    appPile,
    appDeck,
    burned,
    unused,
    pendingAttack: null,
    currentTurn: nextTurn,
    lastDrawTurn: { ...(game.lastDrawTurn || {}), [uid]: nextTurn },
    currentMessage: messageData,
  };

  if (winner) {
    gameUpdate.status = "finished";
    gameUpdate.winner = winner;

    // Update winner's score in Firestore leaderboard
    try {
      const winnerName = game.playerNames[winner] || "Unknown Player";
      const scoreRef = db.collection("scores").doc(winner);

      await db.runTransaction(async (tx) => {
        const scoreDoc = await tx.get(scoreRef);

        if (scoreDoc.exists) {
          const currentWins = scoreDoc.data().wins || 0;
          tx.update(scoreRef, {
            wins: currentWins + 1,
            playerName: winnerName,
          });
        } else {
          tx.set(scoreRef, {
            uid: winner,
            playerName: winnerName,
            wins: 1,
          });
        }
      });

      console.log(`Updated leaderboard for winner: ${winnerName} (${winner})`);
    } catch (error) {
      console.error("Error updating winner's score:", error);
      // Don't fail the game update if leaderboard update fails
    }
  }

  await gameRef.set(gameUpdate);
  return { success: true };
});

// Resign from game
exports.resign = httpsOnCall(async (req) => {
  const { gameId } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!gameId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Game ID required"
    );

  const gameRef = rtdb.ref(`games/${gameId}`);
  const gameSnapshot = await gameRef.once("value");
  const game = gameSnapshot.val();
  if (!game)
    throw new functions.https.HttpsError("not-found", "Game not found");

  await gameRef.set({
    ...game,
    status: "resigned",
    resignedBy: uid,
    resignedAt: admin.database.ServerValue.TIMESTAMP,
  });

  return { success: true };
});

// Create lobby
exports.createLobby = httpsOnCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");

  // Check if user is already in any lobby
  const allLobbiesSnapshot = await rtdb.ref("lobbies").once("value");
  const allLobbies = allLobbiesSnapshot.val();
  if (allLobbies) {
    for (const [existingLobbyId, existingLobby] of Object.entries(allLobbies)) {
      if (
        existingLobby &&
        existingLobby.players &&
        existingLobby.players.includes(uid)
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Already in another lobby"
        );
      }
    }
  }

  const userSnapshot = await rtdb.ref(`onlineUsers/${uid}`).once("value");
  const userData = userSnapshot.val();
  const userName = userData?.displayName || "Unknown Player";

  const lobbyRef = rtdb.ref("lobbies").push();
  await lobbyRef.set({
    createdAt: admin.database.ServerValue.TIMESTAMP,
    players: [uid],
    playerNames: { [uid]: userName },
    creatorId: uid,
    creatorName: userName, // ← Add this for frontend display
    status: "waiting",
  });

  return { lobbyId: lobbyRef.key };
});

// Join lobby
exports.joinLobby = httpsOnCall(async (req) => {
  const { lobbyId } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!lobbyId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Lobby ID required"
    );

  // Check if user is already in any lobby
  const allLobbiesSnapshot = await rtdb.ref("lobbies").once("value");
  const allLobbies = allLobbiesSnapshot.val();
  if (allLobbies) {
    for (const [existingLobbyId, existingLobby] of Object.entries(allLobbies)) {
      if (
        existingLobby &&
        existingLobby.players &&
        existingLobby.players.includes(uid)
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Already in another lobby"
        );
      }
    }
  }

  const lobbyRef = rtdb.ref(`lobbies/${lobbyId}`);
  const lobbySnapshot = await lobbyRef.once("value");
  const lobby = lobbySnapshot.val();
  if (!lobby)
    throw new functions.https.HttpsError("not-found", "Lobby not found");

  const players = lobby.players || [];
  if (players.length >= 4)
    throw new functions.https.HttpsError("failed-precondition", "Lobby full");
  if (players.includes(uid))
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Already in lobby"
    );

  // Get the actual player name from onlineUsers
  const userSnapshot = await rtdb.ref(`onlineUsers/${uid}`).once("value");
  const userData = userSnapshot.val();
  const userName = userData?.displayName || "Unknown Player";

  players.push(uid);
  const playerNames = { ...lobby.playerNames };
  playerNames[uid] = userName; // Use actual player name

  await lobbyRef.set({
    ...lobby,
    players,
    playerNames,
  });

  return { success: true };
});

// Leave lobby
exports.leaveLobby = httpsOnCall(async (req) => {
  const { lobbyId } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!lobbyId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Lobby ID required"
    );

  const lobbyRef = rtdb.ref(`lobbies/${lobbyId}`);
  const lobbySnapshot = await lobbyRef.once("value");
  const lobby = lobbySnapshot.val();
  if (!lobby)
    throw new functions.https.HttpsError("not-found", "Lobby not found");

  const players = lobby.players.filter((p) => p !== uid);
  if (players.length === 0) {
    await lobbyRef.remove();
  } else {
    const playerNames = { ...lobby.playerNames };
    delete playerNames[uid];
    await lobbyRef.set({
      ...lobby,
      players,
      playerNames,
    });
  }

  return { success: true };
});

// Cancel lobby
exports.cancelLobby = httpsOnCall(async (req) => {
  const { lobbyId } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!lobbyId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Lobby ID required"
    );

  await rtdb.ref(`lobbies/${lobbyId}`).remove();
  return { success: true };
});

// Update user online status
exports.updateUserOnlineStatus = httpsOnCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");

  const userDoc = await admin.auth().getUser(uid);
  await rtdb.ref(`onlineUsers/${uid}`).set({
    uid: uid,
    displayName: userDoc.displayName || "Unknown User",
    lastActive: admin.database.ServerValue.TIMESTAMP,
  });

  return { success: true };
});

// Remove user online status
exports.removeUserOnlineStatus = httpsOnCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");

  await rtdb.ref(`onlineUsers/${uid}`).remove();
  return { success: true };
});

// Get all player scores (leaderboard) - still in Firestore
exports.getPlayerScores = httpsOnCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  }

  const scoresSnapshot = await db
    .collection("scores")
    .orderBy("wins", "desc")
    .limit(100)
    .get();

  const scores = [];
  scoresSnapshot.forEach((doc) => {
    scores.push(doc.data());
  });

  return { scores };
});

// Update winner's score when game ends - still in Firestore
exports.updateWinnerScore = httpsOnCall(async (req) => {
  const { winnerId, winnerName } = req.data;
  const uid = req.auth?.uid;

  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  }

  if (!winnerId || !winnerName) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Winner ID and name required"
    );
  }

  const scoreRef = db.collection("scores").doc(winnerId);

  await db.runTransaction(async (tx) => {
    const scoreDoc = await tx.get(scoreRef);

    if (scoreDoc.exists) {
      const currentWins = scoreDoc.data().wins || 0;
      tx.update(scoreRef, {
        wins: currentWins + 1,
        playerName: winnerName,
      });
    } else {
      tx.set(scoreRef, {
        uid: winnerId,
        playerName: winnerName,
        wins: 1,
      });
    }
  });

  return { success: true };
});

// Return to lobby (add user to exitedPlayers)
exports.returnToLobby = httpsOnCall(async (req) => {
  const { gameId } = req.data;
  const uid = req.auth?.uid;
  if (!uid)
    throw new functions.https.HttpsError("unauthenticated", "Not signed in");
  if (!gameId)
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Game ID required"
    );

  const gameRef = rtdb.ref(`games/${gameId}`);
  const gameSnapshot = await gameRef.once("value");
  const game = gameSnapshot.val();
  if (!game)
    throw new functions.https.HttpsError("not-found", "Game not found");

  const exitedPlayers = game.exitedPlayers || [];
  const resignedPlayers = game.resignedPlayers || [];

  // Add current user to exited players if not already there
  if (!exitedPlayers.includes(uid)) {
    exitedPlayers.push(uid);
  }

  // Update the game with the new exitedPlayers list
  await gameRef.update({ exitedPlayers });

  // If all 4 unique players have exited (including resigned players), delete the game
  const allPlayers = new Set([...exitedPlayers, ...resignedPlayers]);
  if (allPlayers.size >= 4) {
    await gameRef.remove();
  }

  return { success: true };
});

// Trigger when lobby is filled
exports.onLobbyFilled = onValueWritten(
  { ref: "/lobbies/{lobbyId}", region: "us-central1" },
  async (event) => {
    const lobby = event.data.after.val();
    if (!lobby || !lobby.players || lobby.players.length !== 4) return;

    const lobbyId = event.params.lobbyId;
    const playerIds = lobby.players;
    const playerNames = lobby.playerNames;

    // Create game
    const gameRef = rtdb.ref("games").push();
    const gameId = gameRef.key;

    // Initialize deck according to project specification
    const appDeck = [];

    // 10 App cards worth 1 point
    for (let i = 0; i < 10; i++) {
      appDeck.push({ type: "app", value: 1, id: `app_1_${i}` });
    }

    // 8 App cards worth 2 points
    for (let i = 0; i < 8; i++) {
      appDeck.push({ type: "app", value: 2, id: `app_2_${i}` });
    }

    // 6 App cards worth 3 points
    for (let i = 0; i < 6; i++) {
      appDeck.push({ type: "app", value: 3, id: `app_3_${i}` });
    }

    // 4 App cards worth 4 points
    for (let i = 0; i < 4; i++) {
      appDeck.push({ type: "app", value: 4, id: `app_4_${i}` });
    }

    const nonAppDeck = [];

    // 30 Download App cards
    for (let i = 0; i < 30; i++) {
      nonAppDeck.push({ type: "Download App", id: `download_${i}` });
    }

    // 20 Computer Virus cards
    for (let i = 0; i < 20; i++) {
      nonAppDeck.push({ type: "Computer Virus", id: `virus_${i}` });
    }

    // 20 Hacker Theft cards
    for (let i = 0; i < 20; i++) {
      nonAppDeck.push({ type: "Hacker Theft", id: `hacker_${i}` });
    }

    // 15 IT Guy cards
    for (let i = 0; i < 15; i++) {
      nonAppDeck.push({ type: "IT Guy", id: `itguy_${i}` });
    }

    // 15 Firewall cards
    for (let i = 0; i < 15; i++) {
      nonAppDeck.push({ type: "Firewall", id: `firewall_${i}` });
    }

    const unused = shuffle(nonAppDeck);
    const playerOrder = shuffle([...playerIds]);

    // Deal initial hands
    const hands = {};
    for (const playerId of playerOrder) {
      hands[playerId] = [];
      for (let i = 0; i < 3; i++) {
        if (unused.length > 0) {
          hands[playerId].push(unused.pop());
        }
      }
    }

    await gameRef.set({
      players: playerIds, // ← Add this for frontend compatibility
      playerOrder, // ← Keep this for game logic
      playerNames,
      hands,
      appDeck: shuffle(appDeck),
      appPile: [],
      burned: [],
      unused,
      currentTurn: 0,
      status: "active",
      createdAt: admin.database.ServerValue.TIMESTAMP,
      lastDrawTurn: {},
      pendingAttack: null,
      currentMessage: null,
    });

    // Remove lobby
    await rtdb.ref(`lobbies/${lobbyId}`).remove();
  }
);
