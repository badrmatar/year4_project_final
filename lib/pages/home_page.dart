import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/stats_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  /// Combines home stats with team points.
  Future<Map<String, dynamic>> _getCombinedStats(int userId) async {
    final homeStats = await StatsService().getHomeStats(userId);
    final teamPoints = await StatsService().getTeamPointsForUser(userId);
    homeStats['teamPoints'] = teamPoints;
    return homeStats;
  }

  /// Retrieves the active league room ID for the user.
  Future<int?> _getLeagueRoomId(int userId) async {
    final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/get_active_league_room_id';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({'user_id': userId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['league_room_id'] as int?;
      }
    } catch (e) {
      // Handle error if needed.
    }
    return null;
  }

  /// Calls the logout function and returns true on success.
  Future<bool> _logoutUser(int userId) async {
    final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/user_logout';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({'user_id': userId}),
      );
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserModel>(context);
    final int userId = user.id;

    return FutureBuilder<Map<String, dynamic>>(
      future: _getCombinedStats(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1F1F1F),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF1F1F1F),
            body: Center(
                child: Text("Error loading stats",
                    style: TextStyle(color: Colors.white))),
          );
        }
        final stats = snapshot.data!;
        // Expected keys: 'userName', 'dailyStreak', 'distanceToday',
        // 'challengeTimeRemaining', 'challengeProgressPercent',
        // 'challengeDistanceCompleted', 'challengeTotalDistance',
        // 'teamPoints', 'teamRank', 'teamName'
        return Scaffold(
          backgroundColor: const Color(0xFF1F1F1F),
          body: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // TOP HEADER (Welcome & Logout)
                        Container(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 48,
                            bottom: 24,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Welcome text and username
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Welcome back",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFFA779FF),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    stats['userName'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              // Logout Button with new gradient color scheme
                              GestureDetector(
                                onTap: () async {
                                  final success = await _logoutUser(userId);
                                  if (success) {
                                    Navigator.pushReplacementNamed(context, '/login');
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Logout failed")),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Colors.deepOrange, Colors.orangeAccent],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.logout, color: Colors.white, size: 18),
                                      SizedBox(width: 4),
                                      Text(
                                        "Logout",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // "Let's get moving" Banner
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: GetMovingBanner(),
                        ),
                        // ACTIVE CHALLENGE CARD
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B9DFF), Color(0xFFB832FA)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title and time remaining
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Daily Team Challenge",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Text(
                                        stats["challengeTimeRemaining"],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Progress bar
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.fitness_center,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: FractionallySizedBox(
                                          widthFactor:
                                          (stats["challengeProgressPercent"] as int) / 100,
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Color(0xFFB832FA),
                                                  Color(0xFF3B9DFF),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.all(Radius.circular(4)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      "${stats["challengeProgressPercent"]}%",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "${stats["challengeDistanceCompleted"].toStringAsFixed(2)}/${stats["challengeTotalDistance"].toStringAsFixed(2)} km completed",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // DAILY STREAK & DISTANCE ROW (moved lower)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                          child: Row(
                            children: [
                              // Daily Streak Widget
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2A2A2A),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 6,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: Colors.greenAccent.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.flash_on,
                                              color: Colors.greenAccent,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            "Daily Streak",
                                            style: TextStyle(fontSize: 14, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "${stats['dailyStreak']} Days",
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Distance Today Widget
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2A2A2A),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 6,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: Colors.blueAccent.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.map,
                                              color: Colors.blueAccent,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            "Distance",
                                            style: TextStyle(fontSize: 14, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "${stats['distanceToday'].toStringAsFixed(2)} km",
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // TEAM STATS CARD (only team points)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Team avatar and info
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFB832FA),
                                            Color(0xFF3B9DFF),
                                          ],
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.emoji_events,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stats["teamName"] ?? "Team",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          "Rank #${stats["teamRank"] ?? '--'}",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                // Total team points only
                                Column(
                                  children: [
                                    Text(
                                      "${stats["teamPoints"] ?? 0}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const Text(
                                      "Total Points",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // SizedBox for extra vertical space
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          bottomNavigationBar: BottomAppBar(
            color: Colors.black.withOpacity(0.8),
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/home');
                    },
                    icon: const Icon(Icons.home),
                    color: Colors.purpleAccent,
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/challenges');
                    },
                    icon: const Icon(Icons.calendar_today),
                    color: Colors.grey,
                  ),
                  IconButton(
                    onPressed: () async {
                      // Check if the user has an active league room.
                      final leagueRoomId = await _getLeagueRoomId(userId);
                      if (leagueRoomId != null) {
                        Navigator.pushReplacementNamed(context, '/league_room');
                      } else {
                        Navigator.pushReplacementNamed(context, '/waiting_room');
                      }
                    },
                    icon: const Icon(Icons.emoji_events),
                    color: Colors.grey,
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/history');
                    },
                    icon: const Icon(Icons.history),
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
