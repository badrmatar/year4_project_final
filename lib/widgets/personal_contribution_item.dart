import 'package:flutter/material.dart';
import '../pages/run_map_view.dart';

class PersonalContributionItem extends StatelessWidget {
  final Map<String, dynamic> contribution;

  const PersonalContributionItem({
    Key? key,
    required this.contribution,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final challenge = contribution['team_challenges']?['challenges'];
    final startTime = DateTime.parse(contribution['start_time']);
    final distance = (contribution['distance_covered'] as num?)?.toDouble() ?? 0.0;
    final routeData = contribution['route'];

    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        title: Text(
          'Run on ${startTime.toLocal().toString().split('.')[0]}',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Distance: ${(distance / 1000).toStringAsFixed(2)} km',
              style: const TextStyle(color: Colors.white70),
            ),
            if (challenge != null) ...[
              Text(
                'Difficulty: ${challenge['difficulty']}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Points: ${challenge['earning_points']}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ],
        ),
        trailing: (routeData != null)
            ? ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RunMapView(routeData: routeData),
              ),
            );
          },
          child: const Text('View Route'),
        )
            : null,
      ),
    );
  }
}