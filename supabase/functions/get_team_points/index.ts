import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// In get_team_points/index.ts
serve(async (req) => {
  try {
    const { league_room_id } = await req.json();

    // First get all teams in the league with their bonus points
    const { data: teamsData, error: teamsError } = await supabase
      .from('teams')
      .select('team_id, streak_bonus_points')
      .eq('league_room_id', league_room_id);

    if (teamsError) throw teamsError;

    // Create a map of team bonuses
    const teamBonuses = teamsData.reduce((acc, team) => {
      acc[team.team_id] = team.streak_bonus_points || 0;
      return acc;
    }, {});

    // Get challenge points
    const { data, error } = await supabase
      .from('team_challenges')
      .select(`
        team_id,
        iscompleted,
        multiplier,
        challenges (
          earning_points
        )
      `)
      .eq('league_room_id', league_room_id);

    if (error) throw error;

    // Calculate points including bonuses
    const teamPoints = data.reduce((acc, challenge) => {
      const teamId = challenge.team_id;
      if (!acc[teamId]) {
        acc[teamId] = {
          team_id: teamId,
          total_points: 0,
          completed_challenges: 0,
          streak_bonus: teamBonuses[teamId] || 0
        };
      }

      if (challenge.iscompleted) {
        const basePoints = challenge.challenges.earning_points;
        const multiplier = challenge.multiplier || 1;
        acc[teamId].total_points += (basePoints * multiplier);
        acc[teamId].completed_challenges += 1;
      }

      return acc;
    }, {});

    // Add bonus points to totals
    Object.values(teamPoints).forEach(team => {
      team.total_points += team.streak_bonus;
    });

    return new Response(
      JSON.stringify({
        data: Object.values(teamPoints)
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
