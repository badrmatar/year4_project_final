// lib/services/team_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamService {
  /// Fetches the active team_id for a user, assuming there's only one active team
  /// (where `date_left` is null). Returns the team_id or null if none found.
  Future<int?> fetchUserTeamId(int userId) async {
    final supabase = Supabase.instance.client;

    try {
      // Query the `team_memberships` table to find the user's active team (date_left IS NULL)
      final response = await supabase
          .from('team_memberships')
          .select('team_id')
          .eq('user_id', userId)
          .filter('date_left', 'is', null) // Use 'is' in raw filter
          .maybeSingle();


      // If no response is returned, return null
      if (response == null) {
        return null;
      }

      // Extract the team_id from the response
      if (response is Map<String, dynamic>) {
        return response['team_id'] as int?;
      }

      return null;
    } catch (e) {
      // Handle errors gracefully
      print('Error fetching user team: $e');
      return null;
    }


  }

  // Fetch the league_id associated with a specific team_id
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
