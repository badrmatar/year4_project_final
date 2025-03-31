import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LeagueService {
  static final String baseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  static final String bearerToken = dotenv.env['BEARER_TOKEN'] ?? '';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $bearerToken',
  };

  static Future<int?> getLeagueRoomId(int userId) async {
    final url = '$baseUrl/functions/v1/get_active_league_room_id';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
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

  static Future<Map<String, dynamic>> getLeagueData(int leagueRoomId) async {
    try {
      final pointsResponse = await http.post(
        Uri.parse('$baseUrl/functions/v1/get_team_points'),
        headers: _headers,
        body: jsonEncode({'league_room_id': leagueRoomId}),
      );

      final membersResponse = await http.post(
        Uri.parse('$baseUrl/functions/v1/get_league_teams'),
        headers: _headers,
        body: jsonEncode({'league_room_id': leagueRoomId}),
      );

      if (pointsResponse.statusCode == 200 && membersResponse.statusCode == 200) {
        final pointsData = jsonDecode(pointsResponse.body);
        final membersData = jsonDecode(membersResponse.body);

        return {
          'pointsData': pointsData,
          'membersData': membersData,
        };
      } else {
        throw Exception('Failed to fetch team data');
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<bool> endLeague(int leagueRoomId) async {
    final url = '$baseUrl/functions/v1/end_league_room';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: jsonEncode({'league_room_id': leagueRoomId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}