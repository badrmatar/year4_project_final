import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/waiting_room_user.dart';

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
  List<WaitingRoomUser> _leagueUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchLeagueRoomData();
  }

  Future<void> _fetchLeagueRoomData() async {
    setState(() => _isLoading = true);

    try {
      // Fetch league room ID for the user
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
      final users = await _fetchLeagueRoomUsers(leagueRoomId);

      setState(() {
        _leagueRoomId = leagueRoomId;
        _leagueRoomName = "League Room $leagueRoomId"; // Placeholder
        _leagueUsers = users;
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
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']!}', // Securely fetch token
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

  Future<List<WaitingRoomUser>> _fetchLeagueRoomUsers(int leagueRoomId) async {
    final url =
        'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_waiting_room_users';

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']!}',
    };

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({'waiting_room_id': leagueRoomId}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => WaitingRoomUser(
        userId: item['user_id'],
        name: item['users']['name'],
        dateJoined: DateTime.parse(item['created_at']),
      ))
          .toList();
    } else {
      throw Exception('Failed to fetch league room users');
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
            itemCount: _leagueUsers.length,
            itemBuilder: (context, index) {
              final user = _leagueUsers[index];
              return ListTile(
                title: Text(user.name),
                subtitle: Text(
                  "Joined: ${user.dateJoined.toLocal().toString().split(' ')[0]}",
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
