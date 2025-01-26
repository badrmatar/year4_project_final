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
  late Future<Map<String, dynamic>> _challengesData;

  @override
  void initState() {
    super.initState();
    _challengesData = _fetchChallengesAndTeamStatus();
  }

  Future<Map<String, dynamic>> _fetchChallengesAndTeamStatus() async {
    final supabase = Supabase.instance.client;
    final user = Provider.of<UserModel>(context, listen: false);
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      // Get today's challenges
      final challengesResponse = await supabase
          .from('challenges')
          .select()
          .gte('start_time', startOfDay.toIso8601String())
          .lt('start_time', endOfDay.toIso8601String());

      // Get user's active team
      final teamMembershipResponse = await supabase
          .from('team_memberships')
          .select('team_id, teams(team_name)')
          .eq('user_id', user.id)
          .filter('date_left', 'is', null)
          .limit(1)
          .single();

      if (teamMembershipResponse == null) {
        throw Exception('No active team membership found');
      }

      final teamId = teamMembershipResponse['team_id'];

      // Get team's active challenges with total distance covered
      final activeTeamChallenges = await supabase
          .from('team_challenges')
          .select('''
            *,
            user_contributions (
              distance_covered
            )
          ''')
          .eq('team_id', teamId)
          .eq('iscompleted', false)
          .order('team_challenge_id', ascending: false);

      // Calculate total distance for each team challenge
      final teamChallengesWithDistance = activeTeamChallenges.map((tc) {
        final contributions = tc['user_contributions'] as List;
        final totalDistance = contributions.fold<double>(
          0,
              (sum, contrib) => sum + (contrib['distance_covered'] ?? 0),
        );
        return {...tc, 'total_distance': totalDistance};
      }).toList();

      debugPrint('Found ${challengesResponse.length} challenges for today');
      debugPrint('Team ID: $teamId');
      debugPrint('Active team challenges: ${teamChallengesWithDistance.length}');

      return {
        'challenges': challengesResponse,
        'teamId': teamId,
        'activeTeamChallenge': teamChallengesWithDistance.isNotEmpty
            ? teamChallengesWithDistance.first
            : null,
      };
    } catch (e) {
      debugPrint('Error fetching challenges and team status: $e');
      rethrow;
    }
  }

  Future<void> _handleChallengeAction(Challenge challenge, dynamic activeTeamChallenge, BuildContext context) async {
    if (activeTeamChallenge != null) {
      // If team already has an active challenge, go straight to run page
      Navigator.pushNamed(context, '/active_run');
      return;
    }

    // Otherwise, assign new challenge to team
    await _assignChallengeToTeam(challenge.challengeId, context);
  }

  Future<void> _assignChallengeToTeam(int challengeId, BuildContext context) async {
    final user = Provider.of<UserModel>(context, listen: false);
    final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/assign_challenge_to_team';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({
          'user_id': user.id,
          'challenge_id': challengeId,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _challengesData = _fetchChallengesAndTeamStatus();
        });
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
      appBar: AppBar(title: const Text("Today's Challenges")),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _challengesData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData ||
              (snapshot.data!['challenges'] as List).isEmpty) {
            return const Center(child: Text('No challenges found for today.'));
          }

          final data = snapshot.data!;
          final challenges = (data['challenges'] as List)
              .map((item) => Challenge.fromJson(item))
              .toList();
          final activeTeamChallenge = data['activeTeamChallenge'];

          return ListView.builder(
            itemCount: challenges.length,
            itemBuilder: (context, index) {
              final challenge = challenges[index];
              final isActiveChallenge = activeTeamChallenge != null &&
                  activeTeamChallenge['challenge_id'] == challenge.challengeId;
              final totalDistance = isActiveChallenge
                  ? (activeTeamChallenge['total_distance'] as double) / 1000 // Convert to km
                  : 0.0;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Challenge #${challenge.challengeId}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isActiveChallenge)
                        Text(
                          '${totalDistance.toStringAsFixed(2)} km',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    'Difficulty: ${challenge.difficulty}\n'
                        'Points: ${challenge.earningPoints}\n'
                        'Start: ${challenge.startTime}\n'
                        'Duration: ${challenge.duration} mins',
                  ),
                  trailing: ElevatedButton(
                    onPressed: activeTeamChallenge != null && !isActiveChallenge
                        ? null  // Disable button if team has different challenge
                        : () => _handleChallengeAction(challenge, activeTeamChallenge, context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActiveChallenge ? Colors.lightGreen : null,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: Text(
                      isActiveChallenge ? 'Continue Run' : 'Start Run',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}