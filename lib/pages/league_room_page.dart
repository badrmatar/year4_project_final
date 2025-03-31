import 'package:flutter/material.dart';
import '../widgets/league_table_header.dart';
import '../widgets/league_team_item.dart';
import '../widgets/empty_league_state.dart';
import '../services/league_service.dart';
import '../widgets/loading_indicator.dart';

class LeagueRoomPage extends StatefulWidget {
  final int userId;

  const LeagueRoomPage({Key? key, required this.userId}) : super(key: key);

  @override
  _LeagueRoomPageState createState() => _LeagueRoomPageState();
}

class _LeagueRoomPageState extends State<LeagueRoomPage> {
  bool _isLoading = true;
  int? _leagueRoomId;
  String? _leagueRoomName;
  List<Map<String, dynamic>> _leagueTeams = [];
  int? _ownerId;

  @override
  void initState() {
    super.initState();
    _fetchLeagueRoomData();
  }

  // Clean team name
  String _getCleanTeamName(String teamName) {
    final regex = RegExp(r'^(.*?)(?:\s*\d+)?$');
    final match = regex.firstMatch(teamName);
    return match != null ? match.group(1)?.trim() ?? teamName : teamName;
  }

  Future<void> _fetchLeagueRoomData() async {
    setState(() => _isLoading = true);

    try {
      final leagueRoomId = await LeagueService.getLeagueRoomId(widget.userId);

      if (leagueRoomId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final leagueData = await LeagueService.getLeagueData(leagueRoomId);
      final pointsData = leagueData['pointsData'];
      final membersData = leagueData['membersData'];

      final pointsList = List<Map<String, dynamic>>.from(pointsData['data'] ?? []);
      final membersList = List<Map<String, dynamic>>.from(membersData['teams'] ?? []);

      List<Map<String, dynamic>> teamsWithPoints = membersList.map((memberTeam) {
        final matchingPoints = pointsList.firstWhere(
              (pt) => pt['team_id'] == memberTeam['team_id'],
          orElse: () => {'total_points': 0, 'completed_challenges': 0},
        );

        int? currentStreak;
        if (memberTeam['teams'] != null) {
          if (memberTeam['teams'] is Map) {
            currentStreak = memberTeam['teams']['current_streak'];
          } else if (memberTeam['teams'] is List && memberTeam['teams'].isNotEmpty) {
            currentStreak = memberTeam['teams'][0]['current_streak'];
          }
        }
        currentStreak ??= 0;

        return {
          ...matchingPoints,
          ...memberTeam,
          'current_streak': currentStreak,
        };
      }).toList();

      setState(() {
        _leagueRoomId = leagueRoomId;
        _leagueRoomName = "League Room $leagueRoomId";
        _leagueTeams = teamsWithPoints;
        _ownerId = membersData['owner_id'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error fetching league room data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching league room data: $e')),
        );
      }
    }
  }

  Widget _buildLeagueRoomDetails() {
    _leagueTeams.sort((a, b) => (b['total_points'] ?? 0).compareTo(a['total_points'] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LeagueTableHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: _leagueTeams.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              return LeagueTeamItem(
                team: _leagueTeams[index],
                index: index,
                getCleanTeamName: _getCleanTeamName,
              );
            },
          ),
        ),
        if (_ownerId == widget.userId)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _handleEndLeague,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB832FA),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'End League',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleEndLeague() async {
    if (_leagueRoomId == null) return;
    setState(() => _isLoading = true);

    try {
      final success = await LeagueService.endLeague(_leagueRoomId!);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('League ended successfully!')),
        );
        Navigator.pushReplacementNamed(context, '/home');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to end league')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ending league: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/home');
          },
        ),
        title: const Text("League Room", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1F1F1F),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isLoading
          ? const LoadingIndicator()
          : _leagueTeams.isEmpty
          ? const EmptyLeagueState()
          : _buildLeagueRoomDetails(),
    );
  }
}