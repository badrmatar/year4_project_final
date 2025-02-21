import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

import '../models/waiting_room_user.dart';

final String bearerToken = dotenv.env['BEARER_TOKEN']!;

Future<int?> getWaitingRoomId(int userId) async {
  final url = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_waiting_room_id';
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $bearerToken'
  };

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({'userId': userId}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['waiting_room_id'];
    } else {
      print('Error fetching waiting room: ${response.body}');
      return null;
    }
  } catch (e) {
    print('Exception in getWaitingRoomId: $e');
    return null;
  }
}

Future<int?> getLeagueRoomId(int userId) async {
  final url = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_active_league_room_id';
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $bearerToken',
  };

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({'user_id': userId}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['league_room_id'];
    } else {
      print('Error fetching league room: ${response.body}');
      return null;
    }
  } catch (e) {
    print('Exception in getLeagueRoomId: $e');
    return null;
  }
}

Future<int?> createWaitingRoom(int userId) async {
  final url = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/create_waiting_room';
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $bearerToken',
  };

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({'userId': userId}),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['waiting_room_id'];
    } else {
      print('Error creating waiting room: ${response.body}');
      return null;
    }
  } catch (e) {
    print('Exception in createWaitingRoom: $e');
    return null;
  }
}

Future<bool> joinWaitingRoom(int userId, int waitingRoomId) async {
  final url = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/join_waiting_room';
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $bearerToken',
  };

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({
        'userId': userId,
        'waitingRoomId': waitingRoomId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return true;
    } else {
      print('Error joining waiting room: ${response.body}');
      return false;
    }
  } catch (e) {
    print('Exception in joinWaitingRoom: $e');
    return false;
  }
}

Future<bool> createLeagueRoom(int userId) async {
  final url = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/create_league_room';
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $bearerToken',
  };

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({ 'user_id': userId }),
    );

    if (response.statusCode == 200) {
      print('League room created successfully: ${response.body}');
      return true;
    } else {
      print('Error starting league room: ${response.body}');
      return false;
    }
  } catch (e) {
    print('Exception in startLeagueRoom: $e');
    return false;
  }
}

Future<List<WaitingRoomUser>> fetchWaitingRoomUsers(int waitingRoomId) async {
  final url = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_waiting_room_users';
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $bearerToken',
  };

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({ 'waiting_room_id': waitingRoomId }),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      final List<WaitingRoomUser> users = data.map((item) {
        final userId = item['user_id'] as int;
        final dateJoinedString = item['created_at'] as String;
        final dateJoined = DateTime.parse(dateJoinedString);
        final userName = item['users']?['name'] as String? ?? 'Unknown';

        return WaitingRoomUser(
          userId: userId,
          name: userName,
          dateJoined: dateJoined,
        );
      }).toList();

      return users;
    } else {
      print('Error fetching waiting room users: ${response.body}');
      return [];
    }
  } catch (e) {
    print('Exception in fetchWaitingRoomUsers: $e');
    return [];
  }
}

class WaitingRoomScreen extends StatefulWidget {
  final int userId;
  const WaitingRoomScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _WaitingRoomScreenState createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  bool _isLoading = true;
  int? _waitingRoomId;
  int? _leagueRoomId;
  List<WaitingRoomUser> _waitingRoomUsers = [];

  final TextEditingController _waitingRoomIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeLogic();
  }

  Future<void> _initializeLogic() async {
    setState(() => _isLoading = true);

    int? fetchedWaitingRoomId = await getWaitingRoomId(widget.userId);

    if (fetchedWaitingRoomId != null) {
      _waitingRoomId = fetchedWaitingRoomId;
      _waitingRoomUsers = await fetchWaitingRoomUsers(fetchedWaitingRoomId);
    } else {
      int? fetchedLeagueRoomId = await getLeagueRoomId(widget.userId);
      _leagueRoomId = fetchedLeagueRoomId;
    }

    setState(() => _isLoading = false);
  }

  Future<void> _handleCreateWaitingRoom() async {
    setState(() => _isLoading = true);
    final newWaitingRoomId = await createWaitingRoom(widget.userId);
    if (newWaitingRoomId != null) {
      _waitingRoomId = newWaitingRoomId;
      _waitingRoomUsers = await fetchWaitingRoomUsers(newWaitingRoomId);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _handleJoinWaitingRoom() async {
    final inputText = _waitingRoomIdController.text.trim();
    if (inputText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a waiting room ID.")));
      return;
    }

    final waitingRoomIdToJoin = int.tryParse(inputText);
    if (waitingRoomIdToJoin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid waiting room ID format.")));
      return;
    }

    setState(() => _isLoading = true);
    final success = await joinWaitingRoom(widget.userId, waitingRoomIdToJoin);
    if (success) {
      _waitingRoomId = waitingRoomIdToJoin;
      _waitingRoomUsers = await fetchWaitingRoomUsers(waitingRoomIdToJoin);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to join waiting room.")));
    }
    setState(() => _isLoading = false);
  }

  Future<void> _handleStartLeague() async {
    setState(() => _isLoading = true);

    final success = await createLeagueRoom(widget.userId);
    if (success) {
      _waitingRoomId = null;
      final newLeagueRoomId = await getLeagueRoomId(widget.userId);
      if (newLeagueRoomId != null) {
        _leagueRoomId = newLeagueRoomId;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("League Room started successfully!")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to start league room.")),
      );
    }

    setState(() => _isLoading = false);
  }

  Widget _buildWaitingRoomView() {
    if (_waitingRoomUsers.isEmpty) {
      return Center(
        child: Text(
          "Waiting Room ID: $_waitingRoomId\nNo users found.",
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }

    _waitingRoomUsers.sort((a, b) => a.dateJoined.compareTo(b.dateJoined));
    final oldestUser = _waitingRoomUsers.first;
    bool isCurrentUserOldest = (oldestUser.userId == widget.userId);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            "Waiting Room ID: $_waitingRoomId",
            style: const TextStyle(fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _waitingRoomUsers.length,
              itemBuilder: (context, index) {
                final user = _waitingRoomUsers[index];
                final joinedStr = user.dateJoined.toString();
                return ListTile(
                  title: Text(
                    user.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'User ID: ${user.userId} | Joined: $joinedStr',
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              },
            ),
          ),
          if (isCurrentUserOldest)
            ElevatedButton(
              onPressed: _handleStartLeague,
              child: const Text("Start"),
            ),
        ],
      ),
    );
  }

  Widget _buildCreateJoinOptions() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          ElevatedButton(
            onPressed: _handleCreateWaitingRoom,
            child: const Text("Create Waiting Room"),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _waitingRoomIdController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Enter Waiting Room ID to join",
              border: OutlineInputBorder(),
              labelStyle: TextStyle(color: Colors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white70),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _handleJoinWaitingRoom,
            child: const Text("Join Waiting Room"),
          ),
        ],
      ),
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
        title: const Text("Waiting Room", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/home');
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _waitingRoomId != null
          ? _buildWaitingRoomView()
          : _leagueRoomId != null
          ? Center(
        child: Text(
          "You are already in a League Room (ID: $_leagueRoomId).",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      )
          : _buildCreateJoinOptions(),
    );
  }
}
