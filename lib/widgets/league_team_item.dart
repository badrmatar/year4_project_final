import 'package:flutter/material.dart';

class LeagueTeamItem extends StatelessWidget {
  final Map<String, dynamic> team;
  final int index;
  final String Function(String) getCleanTeamName;

  const LeagueTeamItem({
    Key? key,
    required this.team,
    required this.index,
    required this.getCleanTeamName,
  }) : super(key: key);

  Widget _buildStreakIndicator(int? streak) {
    final actualStreak = streak ?? 0;
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: actualStreak > 0 ? Colors.orange.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department,
            size: 12,
            color: actualStreak > 0 ? Colors.orange : Colors.grey.shade400,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              "$actualStreak d",
              style: TextStyle(
                fontSize: 12,
                color: actualStreak > 0 ? Colors.orange : Colors.grey.shade400,
                fontWeight: actualStreak > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTopThree = index < 3;
    final members = (team['members'] as List?)
        ?.map((m) => m['users']?['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList() ??
        [];
    final memberNames = members.join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                "${index + 1}",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isTopThree ? Colors.white : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    getCleanTeamName(team['team_name'] ?? ''),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isTopThree ? FontWeight.w600 : FontWeight.normal,
                      color: Colors.white,
                    ),
                  ),
                  if (memberNames.isNotEmpty)
                    Text(
                      memberNames,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  "${team['total_points'] ?? 0}",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isTopThree ? Colors.amber.shade700 : Colors.white,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: _buildStreakIndicator(team['current_streak'] ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}