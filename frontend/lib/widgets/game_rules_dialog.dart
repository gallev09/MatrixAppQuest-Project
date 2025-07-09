import 'package:flutter/material.dart';

class GameRulesDialog extends StatelessWidget {
  const GameRulesDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF39FF14), width: 2),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '🎮 App Quest - Game Rules',
                    style: TextStyle(
                      color: Color(0xFF39FF14),
                      fontSize: MediaQuery.of(context).size.width < 400 ? 14 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF39FF14),
                    size: 28,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      '🎯 Objective',
                      'Be the first player to collect 7 points worth of App cards!',
                    ),
                    _buildSection(
                      '🃏 Starting the Game',
                      '• Each player starts with 3 non-App cards\n• Always maintain 3 cards in hand',
                    ),
                    _buildSection(
                      '⚡ Your Turn',
                      '• Play one card from your hand\n  Or discard a card to pass your turn',
                    ),
                    _buildSection(
                      '📱 App Cards',
                      '• Download App: Draw a random App card (1-4 points)\n• Collect Apps to earn points toward victory',
                    ),
                    _buildSection(
                      '🦹 Attack Cards',
                      '• Computer Virus: Force opponent to return a random App\n• Hacker Theft: Steal a random App from opponent\n• Select target when playing these cards',
                    ),
                    _buildSection(
                      '🛡️ Defense Cards',
                      '• Firewall: Blocks Computer Virus attacks\n• IT Guy: Blocks Hacker Theft attacks\n• Both cards go to burned pile when used',
                    ),
                    _buildSection(
                      '🔥 Card Piles',
                      '• Burned: Used cards go here\n• Unused: Draw new cards from here\n• App Deck: Contains all App cards',
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39FF14).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF39FF14), width: 1),
                      ),
                      child: const Text(
                        '💡 Tip: Strategic timing of attacks and defenses is key to victory!',
                        style: TextStyle(
                          color: Color(0xFF39FF14),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF39FF14),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
} 