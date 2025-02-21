import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';


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


  // Clean team name by removing trailing numbers.
  String _getCleanTeamName(String teamName) {
    final regex = RegExp(r'^(.*?)(?:\s*\d+)?$');
    final match = regex.firstMatch(teamName);
    return match != null ? match.group(1)?.trim() ?? teamName : teamName;
  }


  Future<void> _fetchLeagueRoomData() async {
    setState(() => _isLoading = true);


    try {
      final leagueRoomId = await _getLeagueRoomId(widget.userId);


      if (leagueRoomId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }


      final pointsResponse = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/get_team_points'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({'league_room_id': leagueRoomId}),
      );


      final membersResponse = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/get_league_teams'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({'league_room_id': leagueRoomId}),
      );


      if (pointsResponse.statusCode == 200 && membersResponse.statusCode == 200) {
        final pointsData = jsonDecode(pointsResponse.body);
        final membersData = jsonDecode(membersResponse.body);


        final pointsList =
        List<Map<String, dynamic>>.from(pointsData['data'] ?? []);
        final membersList =
        List<Map<String, dynamic>>.from(membersData['teams'] ?? []);


        List<Map<String, dynamic>> teamsWithPoints = membersList.map((memberTeam) {
          final matchingPoints = pointsList.firstWhere(
                (pt) => pt['team_id'] == memberTeam['team_id'],
            orElse: () => {'total_points': 0, 'completed_challenges': 0},
          );


          int? currentStreak;
          if (memberTeam['teams'] != null) {
            if (memberTeam['teams'] is Map) {
              currentStreak = memberTeam['teams']['current_streak'];
            } else if (memberTeam['teams'] is List &&
                memberTeam['teams'].isNotEmpty) {
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
      } else {
        throw Exception('Failed to fetch team data');
      }
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


  Future<int?> _getLeagueRoomId(int userId) async {
    final url =
        '${dotenv.env['SUPABASE_URL']}/functions/v1/get_active_league_room_id';
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
    };


    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({'user_id': userId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['league_room_id'] as int?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }


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


  Widget _buildLeagueRoomDetails() {
    _leagueTeams.sort((a, b) =>
        (b['total_points'] ?? 0).compareTo(a['total_points'] ?? 0));


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row for the league room details
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 32),
                Expanded(
                  flex: 3,
                  child: Text(
                    "TEAM",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      "PTS",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      "STREAK",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _leagueTeams.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final team = _leagueTeams[index];
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
                      Container(
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
                              _getCleanTeamName(team['team_name'] ?? ''),
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
    final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/end_league_room';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({'league_room_id': _leagueRoomId}),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('League ended successfully!')),
          );
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        final errorData = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorData['error'] ?? 'Failed to end league')),
          );
        }
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
          ? const Center(child: CircularProgressIndicator())
          : _leagueTeams.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_off,
              size: 64,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 16),
            Text(
              "No active league room found",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade300,
              ),
            ),
          ],
        ),
      )
          : _buildLeagueRoomDetails(),
    );
  }
}
