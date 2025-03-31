import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/stats_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  Future<Map<String, dynamic>> _getCombinedStats(int userId) async {
    final homeStats = await StatsService().getHomeStats(userId);
    final teamPoints = await StatsService().getTeamPointsForUser(userId);
    homeStats['teamPoints'] = teamPoints;
    return homeStats;
  }

  Future<int?> _getLeagueRoomId(int userId) async {
    final url =
        '${dotenv.env['SUPABASE_URL']}/functions/v1/get_active_league_room_id';
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
    }
    return null;
  }

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
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Widget _buildTipCard({
    required IconData icon,
    required Color iconColor,
    required String text,
    required Gradient gradient,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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
        return Scaffold(
          backgroundColor: const Color(0xFF1F1F1F),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header (Welcome & Logout)
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Wrap welcome text in Expanded to prevent overflow.
                      Expanded(
                        child: Column(
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
                      ),
                      // Wrap logout button in Flexible so it can shrink if needed.
                      Flexible(
                        child: GestureDetector(
                          onTap: () async {
                            final success = await _logoutUser(userId);
                            if (success) {
                              Navigator.pushReplacementNamed(context, '/login');
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("Logout failed")),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.deepOrange, Colors.orangeAccent],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.logout,
                                    color: Colors.white, size: 18),
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
                      ),
                    ],
                  ),
                ),
                // Daily Streak Component
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                                color:
                                Colors.greenAccent.withOpacity(0.1),
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
                              style:
                              TextStyle(fontSize: 14, color: Colors.grey),
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
                // Team Stats Card (with total points in place of rank)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        // Team avatar.
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
                        // Team name and total points.
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
                              "${stats["teamPoints"] ?? 0} Total Points",
                              style: const TextStyle(
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
                const SizedBox(height: 16),
                // Expanded Tips & Tricks Section.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        const Text(
                          "TIPS & TRICKS",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTipCard(
                          icon: Icons.emoji_events,
                          iconColor: Colors.amber,
                          text:
                          "Get DOUBLE the challenge points if you run half the distance with your teammate!",
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF3B9DFF),
                              Color(0xFF00C6FF)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTipCard(
                          icon: Icons.local_fire_department,
                          iconColor: Colors.orange,
                          text:
                          "Every 3-day streak you get 100 bonus points! Don't let it end!",
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF8A00),
                              Color(0xFFFF5252)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTipCard(
                          icon: Icons.people,
                          iconColor: Colors.green,
                          text:
                          "Stay close to your runmate during the run - maximum 500m apart!",
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00B09B),
                              Color(0xFF96C93D)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
