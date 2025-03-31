import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/challenge.dart';
import '../models/user.dart';
import '../widgets/challenge_card.dart';

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

  String _getTimeRemaining(DateTime startTime, int? duration) {
    if (duration == null) return 'N/A';
    final endTime = startTime.add(Duration(minutes: duration));
    final now = DateTime.now().toUtc();
    if (now.isAfter(endTime)) return 'Expired';
    final remaining = endTime.difference(now);
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  Future<Map<String, dynamic>> _fetchChallengesAndTeamStatus() async {
    final supabase = Supabase.instance.client;
    final user = Provider.of<UserModel>(context, listen: false);
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      // Fetch today's challenges.
      final challengesResponse = await supabase
          .from('challenges')
          .select()
          .gte('start_time', startOfDay.toIso8601String())
          .lt('start_time', endOfDay.toIso8601String());
      final List challengesList = challengesResponse as List;

      // Fetch the user's active team membership with joined team details.
      final teamMembershipResponse = await supabase
          .from('team_memberships')
          .select('team_id')
          .eq('user_id', user.id)
          .filter('date_left', 'is', null)
          .limit(1)
          .maybeSingle();
      if (teamMembershipResponse == null) {
        throw Exception('No active team membership found');
      }
      final Map teamMembershipData = teamMembershipResponse;
      final teamId = teamMembershipData['team_id'];

      // Fetch the team's active challenges with user contributions.
      final activeTeamChallengesResponse = await supabase
          .from('team_challenges')
          .select('*, user_contributions(distance_covered, journey_type)')
          .eq('team_id', teamId)
          .eq('iscompleted', false)
          .order('team_challenge_id', ascending: false);
      final List activeTeamChallengesList = activeTeamChallengesResponse as List;

      // Calculate total and duo distances.
      final teamChallengesWithDistance = activeTeamChallengesList.map((tc) {
        final contributions = tc['user_contributions'] as List;
        final totalDistance = contributions.fold<double>(
          0,
              (sum, contrib) => sum + (contrib['distance_covered'] ?? 0),
        );
        final duoDistance = contributions
            .where((contrib) => contrib['journey_type'] == 'duo')
            .fold<double>(
          0,
              (sum, contrib) => sum + (contrib['distance_covered'] ?? 0),
        );
        return {
          ...tc,
          'total_distance': totalDistance,
          'duo_distance': duoDistance,
        };
      }).toList();

//check challenge
      dynamic activeTeamChallenge;
      if (teamChallengesWithDistance.isNotEmpty) {
        activeTeamChallenge = teamChallengesWithDistance.first;
        // If the challenge_id of the active challenge is not in today's challenges, then consider it stale.
        bool isTodayChallenge = challengesList.any((c) =>
        c['challenge_id'] == activeTeamChallenge['challenge_id']);
        if (!isTodayChallenge) {
          activeTeamChallenge = null;
        }
      }

      return {
        'challenges': challengesList,
        'activeTeamChallenge': activeTeamChallenge,
      };
    } catch (e) {
      debugPrint('Error fetching challenges and team status: $e');
      rethrow;
    }
  }

  Future<void> _handleChallengeAction(
      Challenge challenge, dynamic activeTeamChallenge, BuildContext context) async {
    if (activeTeamChallenge != null) {
      Navigator.pushNamed(
        context,
        '/journey_type',
        arguments: {
          'challenge_id': challenge.challengeId,
          'team_challenge_id': activeTeamChallenge['team_challenge_id']
        },
      );
      return;
    }
    final success = await _assignChallengeToTeam(challenge.challengeId, context);
    if (success) {
      Navigator.pushNamed(
        context,
        '/journey_type',
        arguments: {'challenge_id': challenge.challengeId},
      );
    }
  }

  Future<bool> _assignChallengeToTeam(int challengeId, BuildContext context) async {
    final user = Provider.of<UserModel>(context, listen: false);
    final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/assign_challenge_to_team';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({'user_id': user.id, 'challenge_id': challengeId}),
      );
      if (response.statusCode == 200) {
        setState(() {
          _challengesData = _fetchChallengesAndTeamStatus();
        });
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorData['error'] ?? 'Failed to start challenge')),
        );
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1F1F1F),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/home');
          },
        ),
        title: const Text(
          "Today's Challenges",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _challengesData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          } else if (!snapshot.hasData ||
              (snapshot.data!['challenges'] as List).isEmpty) {
            return const Center(
              child: Text(
                'No challenges found for today.',
                style: TextStyle(color: Colors.white),
              ),
            );
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
              return ChallengeCard(
                challenge: challenge,
                activeTeamChallenge: activeTeamChallenge,
                onPressed: _handleChallengeAction,
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class GetMovingBanner extends StatelessWidget {
  const GetMovingBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text(
          "Let's",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        Text(
          "get",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        Text(
          "moving",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}