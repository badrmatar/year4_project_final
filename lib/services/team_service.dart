import 'package:supabase_flutter/supabase_flutter.dart';

class TeamService {
  Future<int?> fetchUserTeamId(int userId) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('team_memberships')
          .select('team_id')
          .eq('user_id', userId)
          .filter('date_left', 'is', null)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      if (response is Map<String, dynamic>) {
        return response['team_id'] as int?;
      }

      return null;
    } catch (e) {
      print('Error fetching user team: $e');
      return null;
    }
  }

  Future<int?> fetchLeagueId(int teamId) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('teams')
          .select('league_id')
          .eq('id', teamId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return response['league_id'] as int?;
    } catch (e) {
      print('Error fetching league ID: $e');
      return null;
    }
  }
}
