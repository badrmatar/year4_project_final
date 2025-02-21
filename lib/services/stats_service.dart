import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class StatsService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getHomeStats(int userId) async {
    final DateTime now = DateTime.now().toUtc();
    final Map<String, dynamic> stats = {
      'userName': 'Runner',
      'level': 1,
      'xpToNextLevel': 1000,
      'dailyStreak': 0,
      'challengeDistanceCompleted': 0.0,
      'challengeTotalDistance': 0.0,
      'challengeProgressPercent': 0,
      'challengeTimeRemaining': 'N/A',
      'distanceToday': 0.0,
      'teamPoints': 0,
      'teamRank': '--',
      'teamName': 'No Team'
    };

    try {
      // Get user info
      final userResponse = await supabase
          .from('users')
          .select('name')
          .eq('user_id', userId)
          .maybeSingle();
      if (userResponse != null) {
        stats['userName'] = userResponse['name'] ?? 'Runner';
      }

      // Get active team membership
      final membershipResponse = await supabase
          .from('team_memberships')
          .select('team_id')
          .eq('user_id', userId)
          .filter('date_left', 'is', 'null')
          .maybeSingle();
      if (membershipResponse != null) {
        final teamId = membershipResponse['team_id'];

        // Get team info including league_room_id
        final teamResponse = await supabase
            .from('teams')
            .select('team_name, current_streak, streak_bonus_points, league_room_id')
            .eq('team_id', teamId)
            .maybeSingle();
        if (teamResponse != null) {
          stats['teamName'] = teamResponse['team_name'];
          stats['dailyStreak'] = teamResponse['current_streak'] ?? 0;
          // We'll update teamPoints using getTeamPointsForUser
          stats['teamPoints'] = teamResponse['streak_bonus_points'] ?? 0;
          stats['leagueRoomId'] = teamResponse['league_room_id'];
        }

        // ... (rest of your existing home stats calculations)
      }

      // 5. Calculate today's personal distance
      final startOfDay = DateTime.utc(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final personalResponse = await supabase
          .from('user_contributions')
          .select('distance_covered')
          .eq('user_id', userId)
          .gte('start_time', startOfDay.toIso8601String())
          .lt('start_time', endOfDay.toIso8601String());
      if (personalResponse != null) {
        double todayDistance = 0.0;
        for (var contribution in personalResponse) {
          todayDistance += (contribution['distance_covered'] as num).toDouble();
        }
        stats['distanceToday'] = todayDistance / 1000.0;
      }

      return stats;
    } catch (e, stackTrace) {
      print('Error in getHomeStats: $e');
      print(stackTrace);
      return stats; // Return default values on error
    }
  }


  /// New method that retrieves the full team points from your edge function.
  /// It uses the current user's team membership to fetch the league_room_id,
  /// then posts to your get_team_points endpoint.
  Future<int> getTeamPointsForUser(int userId) async {
    // 1. Get team membership to find team_id.
    final membershipResponse = await supabase
        .from('team_memberships')
        .select('team_id')
        .eq('user_id', userId)
        .filter('date_left', 'is', 'null')
        .maybeSingle();
    if (membershipResponse == null) return 0;
    final teamId = membershipResponse['team_id'];

    // 2. Get team info to get league_room_id.
    final teamResponse = await supabase
        .from('teams')
        .select('league_room_id')
        .eq('team_id', teamId)
        .maybeSingle();
    if (teamResponse == null) return 0;
    final leagueRoomId = teamResponse['league_room_id'];
    if (leagueRoomId == null) return 0;

    // 3. Call your get_team_points edge function.
    final String supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final String bearerToken = dotenv.env['BEARER_TOKEN']!;
    final url = '$supabaseUrl/functions/v1/get_team_points';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
        },
        body: jsonEncode({'league_room_id': leagueRoomId}),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        // Assuming the response is of the form: { "data": [ { "team_id": ..., "total_points": ... }, ... ] }
        final List<dynamic> teamsWithPoints = data["data"] ?? [];
        for (var team in teamsWithPoints) {
          if (team["team_id"] == teamId) {
            return team["total_points"] as int;
          }
        }
      } else {
        print('Error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error in getTeamPointsForUser: $e');
    }
    return 0;
  }
}
