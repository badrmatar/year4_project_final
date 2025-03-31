import 'package:flutter/material.dart';

class TeamChallengeItem extends StatelessWidget {
  final Map<String, dynamic> teamChallenge;

  const TeamChallengeItem({
    Key? key,
    required this.teamChallenge,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final team = teamChallenge['teams'];
    final challenges = team?['team_challenges'] ?? [];

    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.all(8.0),
      child: ExpansionTile(
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        textColor: Colors.white,
        collapsedTextColor: Colors.white,
        title: Text(
          'Team: ${team?['team_name'] ?? 'Unknown Team'}',
          style: const TextStyle(color: Colors.white),
        ),
        children: challenges.map<Widget>((challenge) {
          final challengeDetails = challenge['challenges'];
          return ListTile(
            title: Text(
              'Difficulty: ${challengeDetails?['difficulty'] ?? 'Unknown'}',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distance: ${challengeDetails?['length']?.toString() ?? 'Unknown'} km',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  'Points: ${challengeDetails?['earning_points']?.toString() ?? 'Unknown'}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  'Status: ${challenge['iscompleted'] ? 'Completed' : 'Incomplete'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}