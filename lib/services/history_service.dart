import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> fetchHistoryData(int userId) async {
    try {
      // get team challenges
      final teamResponse = await supabase
          .from('team_memberships')
          .select('''
            team_id,
            teams (
              team_name,
              team_challenges (
                challenge_id,
                iscompleted,
                challenges (
                  difficulty,
                  length,
                  earning_points
                )
              )
            )
          ''')
          .eq('user_id', userId);


      final personalResponse = await supabase
          .from('user_contributions')
          .select('''
            *,
            team_challenges (
              challenges (
                difficulty,
                length,
                earning_points
              )
            )
          ''')
          .eq('user_id', userId)
          .order('start_time', ascending: false);

      return {
        'teamChallenges': teamResponse,
        'personalContributions': personalResponse
      };
    } catch (e) {
      rethrow;
    }
  }
}