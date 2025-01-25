import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/challenge.dart';
import '../models/user.dart';

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
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final response = await supabase
          .from('challenges')
          .select('*')
          .gte('start_time', startOfDay.toIso8601String())
          .lt('start_time', endOfDay.toIso8601String());

      if (response is List) {
        return response.map((item) => Challenge.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching challenges: $e');
      return [];
    }
  }

  Future<void> _assignChallengeToTeam(int challengeId, BuildContext context) async {
    final user = Provider.of<UserModel>(context, listen: false);
    final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/assign_challenge_to_team';
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
    };
    final body = jsonEncode({
      'user_id': user.id,
      'challenge_id': challengeId,
    });

    try {
      final response = await http.post(Uri.parse(url), headers: headers, body: body);
      if (response.statusCode == 200) {
        Navigator.pushNamed(context, '/active_run');
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorData['error'] ?? 'Failed to start challenge')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today’s Challenges")),
      body: FutureBuilder<List<Challenge>>(
        future: _challengesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No challenges found.'));
          }

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
                trailing: ElevatedButton(
                  onPressed: () => _assignChallengeToTeam(c.challengeId, context),
                  child: const Text('Start Run'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}