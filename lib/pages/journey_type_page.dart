import 'package:flutter/material.dart';

class JourneyTypePage extends StatelessWidget {
  const JourneyTypePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final challengeId = args['challenge_id'] as int;
    final teamChallengeId = args.containsKey('team_challenge_id')
        ? args['team_challenge_id'] as int
        : challengeId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Journey Type'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildJourneyCard(
              context,
              title: 'Solo Run',
              icon: Icons.person,
              description: 'Run at your own pace',
              color: Colors.blue,
              onTap: () => _handleSoloRun(context, challengeId),
            ),
            const SizedBox(height: 20),
            _buildJourneyCard(
              context,
              title: 'Duo Run',
              icon: Icons.people,
              description: 'Run together with your teammate\nStay within 400m for bonus points!',
              color: Colors.green,
              onTap: () => _handleDuoRun(context, teamChallengeId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJourneyCard(
      BuildContext context, {
        required String title,
        required IconData icon,
        required String description,
        required Color color,
        required VoidCallback onTap,
      }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[600],
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSoloRun(BuildContext context, int challengeId) {
    Navigator.pushReplacementNamed(
      context,
      '/run_loading',
      arguments: {
        'journey_type': 'solo',
        'challenge_id': challengeId,
      },
    );
  }

  void _handleDuoRun(BuildContext context, int teamChallengeId) {
    Navigator.pushReplacementNamed(
      context,
      '/duo_waiting_room',
      arguments: {
        'team_challenge_id': teamChallengeId,
      },
    );
  }
}