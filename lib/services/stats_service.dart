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
      'distanceSinceLeagueStarted': 0.0,
      'teamPoints': 0,
      'teamRank': '--',
      'teamName': 'No Team'
    };

    try {
      final userResponse = await supabase
          .from('users')
          .select('name')
          .eq('user_id', userId)
          .maybeSingle();
      if (userResponse != null) {
        stats['userName'] = userResponse['name'] ?? 'Runner';
      }

      final membershipResponse = await supabase
          .from('team_memberships')
          .select('team_id')
          .eq('user_id', userId)
          .filter('date_left', 'is', 'null')
          .maybeSingle();

      if (membershipResponse != null) {
        final teamId = membershipResponse['team_id'];

        // get team info
        final teamResponse = await supabase
            .from('teams')
            .select('team_name, current_streak, streak_bonus_points, league_room_id')
            .eq('team_id', teamId)
            .maybeSingle();
        if (teamResponse != null) {
          stats['teamName'] = teamResponse['team_name'];
          stats['dailyStreak'] = teamResponse['current_streak'] ?? 0;
          stats['teamPoints'] = teamResponse['streak_bonus_points'] ?? 0;
          stats['leagueRoomId'] = teamResponse['league_room_id'];
        }

        final activeChallengeResponse = await supabase
            .from('team_challenges')
            .select('''
              *,
              challenges(
                start_time,
                duration,
                length
              ),
              user_contributions(distance_covered)
            ''')
            .eq('team_id', teamId)
            .eq('iscompleted', false)
            .order('team_challenge_id', ascending: false)
            .maybeSingle();

        if (activeChallengeResponse != null) {
          final challengeData = activeChallengeResponse['challenges'];
          if (challengeData != null) {
            final String startTimeStr = challengeData['start_time'];
            final int? duration = challengeData['duration'] as int?;

            if (duration != null) {
              final DateTime startTime = DateTime.parse(startTimeStr);
              final DateTime endTime = startTime.add(Duration(minutes: duration));
              final Duration remaining = endTime.difference(now);
              if (remaining.isNegative) {
                stats['challengeTimeRemaining'] = 'Expired';
              } else {
                final int hours = remaining.inHours;
                final int minutes = remaining.inMinutes % 60;
                stats['challengeTimeRemaining'] =
                hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
              }
            }
            final double totalDistance = (challengeData['length'] ?? 0).toDouble();
            stats['challengeTotalDistance'] = totalDistance;

            final List<dynamic> contributions =
                activeChallengeResponse['user_contributions'] ?? [];
            double totalDistanceCovered = 0.0;
            for (var contrib in contributions) {
              totalDistanceCovered += (contrib['distance_covered'] ?? 0).toDouble();
            }
            final double distanceKm = totalDistanceCovered / 1000.0;
            stats['challengeDistanceCompleted'] = distanceKm;

            // Compute progress percent
            if (totalDistance > 0) {
              stats['challengeProgressPercent'] =
                  ((distanceKm / totalDistance) * 100).toInt();
            }
          }
        }

        final activeMembersResponse = await supabase
            .from('team_memberships')
            .select('user_id')
            .eq('team_id', teamId)
            .filter('date_left', 'is', 'null');
        if (activeMembersResponse != null) {
          final List<int> memberIds = activeMembersResponse
              .map((m) => m['user_id'] as int)
              .toList();
          final memberIdsString = '(${memberIds.join(',')})';
          final contributionsResponse = await supabase
              .from('user_contributions')
              .select('distance_covered')
              .filter('user_id', 'in', memberIdsString);


          double totalTeamDistance = 0.0;
          for (var contrib in contributionsResponse) {
            totalTeamDistance += (contrib['distance_covered'] as num).toDouble();
          }

          stats['distanceSinceLeagueStarted'] = totalTeamDistance / 1000.0;
        }
      }
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
      return stats;
    }
  }

  Future<int> getTeamPointsForUser(int userId) async {
    final membershipResponse = await supabase
        .from('team_memberships')
        .select('team_id')
        .eq('user_id', userId)
        .filter('date_left', 'is', 'null')
        .maybeSingle();
    if (membershipResponse == null) return 0;
    final teamId = membershipResponse['team_id'];

    final teamResponse = await supabase
        .from('teams')
        .select('league_room_id')
        .eq('team_id', teamId)
        .maybeSingle();
    if (teamResponse == null) return 0;
    final leagueRoomId = teamResponse['league_room_id'];
    if (leagueRoomId == null) return 0;

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
        final List<dynamic> teamsWithPoints = data["data"] ?? [];
        for (var team in teamsWithPoints) {
          if (team["team_id"] == membershipResponse['team_id']) {
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
