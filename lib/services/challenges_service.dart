import 'package:http/http.dart' as http;
import 'dart:convert';

class ChallengeService {
  final String supabaseEdgeFunctionUrl = 'https://your-edge-function-url';
  final String apiKey = 'your-supabase-api-key';

  Future<void> createTeamChallenge(int teamId, int challengeId) async {
    final url = Uri.parse('$supabaseEdgeFunctionUrl/create_team_challenges');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'team_id': teamId,
        'challenge_id': challengeId,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create team challenge: ${response.body}');
    }
  }
}
