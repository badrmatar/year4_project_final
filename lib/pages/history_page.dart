// lib/pages/history_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/history_service.dart';
import '../widgets/team_challenge_item.dart';
import '../widgets/personal_contribution_item.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryService _historyService = HistoryService();
  Map<String, dynamic>? _historyData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchHistoryData();
  }

  Future<void> _fetchHistoryData() async {
    try {
      final userModel = Provider.of<UserModel>(context, listen: false);
      final historyData = await _historyService.fetchHistoryData(userModel.id);
      setState(() {
        _historyData = historyData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load history data';
        _isLoading = false;
      });
      print('Error fetching history data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
        ),
        title: const Text('Challenge History'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.white),
        ),
      )
          : _buildHistoryContent(),
    );
  }

  Widget _buildHistoryContent() {
    final teamChallenges = _historyData?['teamChallenges'] ?? [];
    final personalContributions = _historyData?['personalContributions'] ?? [];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'Team Challenges'),
              Tab(text: 'Personal Contributions'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTeamChallengesTab(teamChallenges),
                _buildPersonalContributionsTab(personalContributions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamChallengesTab(List<dynamic> teamChallenges) {
    if (teamChallenges.isEmpty) {
      return const Center(
        child: Text(
          'No team challenges found',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    return ListView.builder(
      itemCount: teamChallenges.length,
      itemBuilder: (context, index) {
        return TeamChallengeItem(teamChallenge: teamChallenges[index]);
      },
    );
  }

  Widget _buildPersonalContributionsTab(List<dynamic> personalContributions) {
    if (personalContributions.isEmpty) {
      return const Center(
        child: Text(
          'No personal contributions found',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    return ListView.builder(
      itemCount: personalContributions.length,
      itemBuilder: (context, index) {
        return PersonalContributionItem(contribution: personalContributions[index]);
      },
    );
  }
}
