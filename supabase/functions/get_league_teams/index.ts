import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const { league_room_id } = await req.json();

    // First get the earliest waiting room entry for this league room
    const { data: waitingRoomData, error: waitingRoomError } = await supabase
      .from('waiting_rooms')
      .select('user_id, created_at')
      .eq('league_room_id', league_room_id)
      .order('created_at', { ascending: true })
      .limit(1)
      .single();

    if (waitingRoomError) throw waitingRoomError;

    const ownerUserId = waitingRoomData.user_id;

    const { data: teamsData, error: teamsError } = await supabase
      .from('teams')
      .select(`
        team_id,
        team_name,
        current_streak,
        members:team_memberships(
          user_id,
          users(name)
        )
      `)
      .eq('league_room_id', league_room_id);

    if (teamsError) throw teamsError;

    console.log('Teams data:', teamsData);

    const teamsWithStreak = teamsData.map(team => ({
      ...team,
      teams: {
        team_name: team.team_name,
        current_streak: team.current_streak || 0
      }
    }));

    console.log('Transformed teams data:', teamsWithStreak);

    return new Response(JSON.stringify({
      teams: teamsWithStreak,
      owner_id: ownerUserId
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Error in get_league_teams:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});