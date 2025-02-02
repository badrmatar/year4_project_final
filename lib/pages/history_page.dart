// lib/pages/history_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _teamChallenges = [];
  List<Map<String, dynamic>> _personalContributions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchHistoryData();
  }

  Future<void> _fetchHistoryData() async {
    final user = Provider.of<UserModel>(context, listen: false);
    final supabase = Supabase.instance.client;

    try {
      // Fetch team challenges
      final teamResponse = await supabase
          .from('team_memberships')
          .select('''
            team_id,
            teams (
              team_name,
              team_challenges (
                challenge_id,
                iscompleted,
                challenges (
                  difficulty,
                  length,
                  earning_points
                )
              )
            )
          ''')
          .eq('user_id', user.id);

      // Fetch personal contributions
      final personalResponse = await supabase
          .from('user_contributions')
          .select('''
            *,
            team_challenges (
              challenges (
                difficulty,
                length,
                earning_points
              )
            )
          ''')
          .eq('user_id', user.id)
          .order('start_time', ascending: false);

      if (mounted) {
        setState(() {
          _teamChallenges = List<Map<String, dynamic>>.from(teamResponse);
          _personalContributions = List<Map<String, dynamic>>.from(personalResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching history: $e')),
        );
      }
    }
  }

  Widget _buildTeamChallenges() {
    if (_teamChallenges.isEmpty) {
      return const Center(child: Text('No team challenges found'));
    }

    return ListView.builder(
      itemCount: _teamChallenges.length,
      itemBuilder: (context, index) {
        final teamChallenge = _teamChallenges[index];
        final team = teamChallenge['teams'];
        final challenges = team?['team_challenges'] ?? [];

        return Card(
          margin: const EdgeInsets.all(8.0),
          child: ExpansionTile(
            title: Text('Team: ${team?['team_name'] ?? 'Unknown Team'}'),
            children: challenges.map<Widget>((challenge) {
              final challengeDetails = challenge['challenges'];
              return ListTile(
                title: Text('Difficulty: ${challengeDetails?['difficulty'] ?? 'Unknown'}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Distance: ${challengeDetails?['length']?.toString() ?? 'Unknown'} km'),
                    Text('Points: ${challengeDetails?['earning_points']?.toString() ?? 'Unknown'}'),
                    Text('Status: ${challenge['iscompleted'] ? 'Completed' : 'Incomplete'}'),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildPersonalContributions() {
    if (_personalContributions.isEmpty) {
      return const Center(child: Text('No personal contributions found'));
    }

    return ListView.builder(
      itemCount: _personalContributions.length,
      itemBuilder: (context, index) {
        final contribution = _personalContributions[index];
        final challenge = contribution['team_challenges']?['challenges'];
        final startTime = DateTime.parse(contribution['start_time']);
        final distance = contribution['distance_covered']?.toDouble() ?? 0.0;

        return Card(
          margin: const EdgeInsets.all(8.0),
          child: ListTile(
            title: Text('Run on ${startTime.toLocal().toString().split('.')[0]}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Distance: ${(distance / 1000).toStringAsFixed(2)} km'),
                if (challenge != null) ...[
                  Text('Difficulty: ${challenge['difficulty']}'),
                  Text('Points: ${challenge['earning_points']}'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Team Accomplishments'),
            Tab(text: 'Personal Contributions'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildTeamChallenges(),
          _buildPersonalContributions(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}