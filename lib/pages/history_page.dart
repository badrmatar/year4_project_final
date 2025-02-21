import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user.dart';
import 'run_map_view.dart'; // For viewing the route

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
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

      // Fetch personal contributions (including the "route" field)
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
          _personalContributions =
          List<Map<String, dynamic>>.from(personalResponse);
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
      return const Center(
        child: Text(
          'No team challenges found',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return ListView.builder(
      itemCount: _teamChallenges.length,
      itemBuilder: (context, index) {
        final teamChallenge = _teamChallenges[index];
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
      },
    );
  }

  Widget _buildPersonalContributions() {
    if (_personalContributions.isEmpty) {
      return const Center(
        child: Text(
          'No personal contributions found',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return ListView.builder(
      itemCount: _personalContributions.length,
      itemBuilder: (context, index) {
        final contribution = _personalContributions[index];
        final challenge = contribution['team_challenges']?['challenges'];
        final startTime = DateTime.parse(contribution['start_time']);
        final distance =
            (contribution['distance_covered'] as num?)?.toDouble() ?? 0.0;
        final routeData = contribution['route']; // This field holds the saved route

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
                // Navigate to the RunMapView screen to display the saved route.
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
      },
    );
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
          'History',
          style: TextStyle(color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.purpleAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
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
