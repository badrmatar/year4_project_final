import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/challenge.dart';

class ChallengesPage extends StatefulWidget {
  const ChallengesPage({Key? key}) : super(key: key);

  @override
  _ChallengesPageState createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> {
  late Future<List<Challenge>> _challengesFuture;

  @override
  void initState() {
    super.initState();
    _challengesFuture = _fetchTodayChallenges();
  }

  Future<List<Challenge>> _fetchTodayChallenges() async {
    final supabase = Supabase.instance.client;

    // Get current date boundaries in UTC
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    debugPrint('Fetching challenges from: $startOfDay to $endOfDay');

    try {
      final response = await supabase
          .from('challenges')
          .select('*')
          .gte('start_time', startOfDay.toIso8601String())
          .lt('start_time', endOfDay.toIso8601String());

      debugPrint('Raw response: $response');

      if (response is List) {
        return response.map((item) => Challenge.fromJson(item)).toList();
      } else {
        debugPrint('Unexpected response format: $response');
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching challenges: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Today’s Challenges"),
      ),
      body: FutureBuilder<List<Challenge>>(
        future: _challengesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No challenges found.'));
          } else {
            final challenges = snapshot.data!;
            return ListView.builder(
              itemCount: challenges.length,
              itemBuilder: (context, index) {
                final c = challenges[index];
                return ListTile(
                  title: Text('Challenge #${c.challengeId}'),
                  subtitle: Text(
                    'Difficulty: ${c.difficulty}\n'
                        'Points: ${c.earningPoints}\n'
                        'Start: ${c.startTime}\n'
                        'Duration: ${c.duration} mins',
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
