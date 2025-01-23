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

  @override
  void initState() {
    super.initState();
    _fetchLeagueRoomData();
  }

  Future<void> _fetchLeagueRoomData() async {
    setState(() => _isLoading = true);

    try {
      print('Debug: Fetching league room for userId ${widget.userId}');
      final leagueRoomId = await _getLeagueRoomId(widget.userId);

      if (leagueRoomId == null) {
        setState(() {
          _isLoading = false;
          _leagueRoomId = null;
        });
        return;
      }

      print('Debug: Found league room ID: $leagueRoomId');
      final teams = await _fetchLeagueTeams(leagueRoomId);

      setState(() {
        _leagueRoomId = leagueRoomId;
        _leagueRoomName = "League Room $leagueRoomId";
        _leagueTeams = teams;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Debug: Exception in _fetchLeagueRoomData: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching league room data: $e')),
      );
    }
  }

  Future<int?> _getLeagueRoomId(int userId) async {
    final url =
        'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_active_league_room_id';

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']!}',
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Debug: API response: $data');
        return data['league_room_id'] as int?;
      } else {
        print('Error: API returned ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception in _getLeagueRoomId: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLeagueTeams(int leagueRoomId) async {
    final url =
        'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_league_teams'; // Fixed typo here

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']!}',
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({'league_room_id': leagueRoomId}),
      );

      print('Debug: Fetching teams for league room $leagueRoomId');
      print('Debug: Response status: ${response.statusCode}');
      print('Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        return List<Map<String, dynamic>>.from(data);
      } else {
        print('Error fetching league teams: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Exception in _fetchLeagueTeams: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("League Room"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _leagueRoomId == null
          ? Center(
        child: Text(
          "No active league room found.",
          style: const TextStyle(fontSize: 18),
        ),
      )
          : _buildLeagueRoomDetails(),
    );
  }

  Widget _buildLeagueRoomDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "League Room: $_leagueRoomName",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: _leagueTeams.length,
            itemBuilder: (context, index) {
              final team = _leagueTeams[index];
              final members = team['members'] as List<dynamic>;

              return ListTile(
                title: Text(
                  "Team: ${team['team_name']}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: members.map<Widget>((member) {
                    return Text("- ${member['name']} (ID: ${member['user_id']})");
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}