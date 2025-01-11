import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dart:convert';

final String bearerToken = dotenv.env['BEARER_TOKEN']!;

/// This function calls the "get_waiting_room_id" Edge Function:
///   POST https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_waiting_room_id
/// Body: { "userId": userId }
/// Returns: waiting_room_id or null if not found
Future<int?> getWaitingRoomId(int userId) async {
  final url =  'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_waiting_room_id';
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
      // The function's response might look like:
      // { "message": "...", "waiting_room_id": 123 } or { "waiting_room_id": null }
      return data['waiting_room_id']; // Could be int or null
    } else {
      // Optionally, parse the error
      print('Error fetching waiting room: ${response.body}');
      return null;
    }
  } catch (e) {
    print('Exception in getWaitingRoomId: $e');
    return null;
  }
}

/// This function calls the "get_active_league_room_id" Edge Function:
///   POST https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_active_league_room_id
/// Body: { "user_id": userId }
/// Returns: league_room_id or null if not found
Future<int?> getLeagueRoomId(int userId) async {
  final url =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/get_active_league_room_id';
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
      // The function's response might look like:
      // { "message": "...", "league_room_id": 456 } or { "league_room_id": null }
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

/// This function calls the "create_waiting_room" Edge Function:
///   POST https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/create_waiting_room
/// Body: { "userId": userId }
/// Returns: newly created waiting_room_id
Future<int?> createWaitingRoom(int userId) async {
  final url =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/create_waiting_room';
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
      // Example response might be:
      // {
      //   "message": "Waiting room created successfully.",
      //   "waiting_room_id": 999,
      //   "created_at": "..."
      // }
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

/// This function calls the "join_waiting_room" Edge Function:
///   POST https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/join_waiting_room
/// Body: { "userId": userId, "waitingRoomId": waitingRoomId }
/// Returns: true if success, false otherwise
Future<bool> joinWaitingRoom(int userId, int waitingRoomId) async {
  final url =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/join_waiting_room';
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

    // If success, the function typically returns a 200 or 201 status
    if (response.statusCode == 200 || response.statusCode == 201) {
      // Optionally parse the body for additional info
      // final data = jsonDecode(response.body);
      // data['waiting_room_id'] etc.
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


/// Fetch the list of users in a specific waiting room. Return user names or emails.
Future<List<String>> fetchWaitingRoomUsers(int waitingRoomId) async {
  // 1) You might have an endpoint to fetch all users in a waiting_room
  // 2) Return a list of user names (or your user model)
  // For demonstration, returning mock data.
  return ['User 1', 'User 2', 'User 3'];
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
  List<String> _waitingRoomUsers = [];

  // For the "join waiting room" action
  final TextEditingController _waitingRoomIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeLogic();
  }

  Future<void> _initializeLogic() async {
    setState(() {
      _isLoading = true;
    });

    // 1) Call get_waiting_room_id(user_id)
    int? fetchedWaitingRoomId = await getWaitingRoomId(widget.userId);

    if (fetchedWaitingRoomId != null) {
      // The user already has a waiting_room_id
      _waitingRoomId = fetchedWaitingRoomId;

      // OPTIONAL: fetch the users in this waiting room for display
      _waitingRoomUsers = await fetchWaitingRoomUsers(fetchedWaitingRoomId);
    } else {
      // 2) If user does not have waiting_room_id, call get_league_room_id(user_id)
      int? fetchedLeagueRoomId = await getLeagueRoomId(widget.userId);
      if (fetchedLeagueRoomId != null) {
        // The user is already in a league room => can't join waiting room
        _leagueRoomId = fetchedLeagueRoomId;
      } else {
        // The user is not in any league room -> Show create or join options
        _leagueRoomId = null;
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  // Handle "Create Waiting Room"
  Future<void> _handleCreateWaitingRoom() async {
    setState(() => _isLoading = true);
    int? newWaitingRoomId = await createWaitingRoom(widget.userId);
    if (newWaitingRoomId != null) {
      _waitingRoomId = newWaitingRoomId;
      // Optionally fetch the waiting room users (should just be the current user at first)
      _waitingRoomUsers = await fetchWaitingRoomUsers(_waitingRoomId!);
    }
    setState(() => _isLoading = false);
  }

  // Handle "Join Waiting Room"
  Future<void> _handleJoinWaitingRoom() async {
    final inputText = _waitingRoomIdController.text.trim();
    if (inputText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a waiting_room_id."))
      );
      return;
    }

    // Convert input to int
    int? waitingRoomIdToJoin = int.tryParse(inputText);
    if (waitingRoomIdToJoin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid waiting_room_id format."))
      );
      return;
    }

    setState(() => _isLoading = true);
    bool success = await joinWaitingRoom(widget.userId, waitingRoomIdToJoin);
    if (success) {
      // Update UI
      _waitingRoomId = waitingRoomIdToJoin;
      _waitingRoomUsers = await fetchWaitingRoomUsers(_waitingRoomId!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to join waiting room."))
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    // Main UI
    return Scaffold(
      appBar: AppBar(title: const Text("Waiting Room Logic")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    // If we have a waiting room
    if (_waitingRoomId != null) {
      return _buildWaitingRoomView();
    }

    // Otherwise, check if we have a league room
    if (_leagueRoomId != null) {
      // Already in a league room => can't join waiting room
      return Center(
        child: Text(
          "You already in League room (ID: $_leagueRoomId). Can't join waiting room.",
          textAlign: TextAlign.center,
        ),
      );
    }

    // Finally, show create/join waiting room options
    return _buildCreateJoinOptions();
  }

  Widget _buildWaitingRoomView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            "Waiting room ID: $_waitingRoomId",
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _waitingRoomUsers.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_waitingRoomUsers[index]),
                );
              },
            ),
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
          // Join waiting room text field + button
          TextField(
            controller: _waitingRoomIdController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Enter Waiting Room ID to join",
              border: OutlineInputBorder(),
            ),
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
}
