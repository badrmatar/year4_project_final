import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Load environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req: Request) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
      });
    }

    let body: any;
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid JSON body.' }), {
        status: 400,
      });
    }

    const { user_id } = body;

    if (typeof user_id !== 'number') {
      return new Response(JSON.stringify({ error: 'user_id must be a number.' }), {
        status: 400,
      });
    }

    // STEP 1: Get the waiting_room_id for this user where league_room_id is NULL.
    const { data: waitingRoomRow, error: findWrError } = await supabase
      .from('waiting_rooms')
      .select('waiting_room_id')
      .eq('user_id', user_id)
      .is('league_room_id', null)
      .maybeSingle();

    if (findWrError || !waitingRoomRow) {
      return new Response(JSON.stringify({
        error: 'No active waiting room found for this user.',
      }), { status: 404 });
    }

    const waiting_room_id = waitingRoomRow.waiting_room_id;

    // STEP 2: Fetch all users in that waiting_room_id (league_room_id still null).
    const { data: waitingUsers, error: waitingUsersError } = await supabase
      .from('waiting_rooms')
      .select('user_id')
      .eq('waiting_room_id', waiting_room_id)
      .is('league_room_id', null);

    if (waitingUsersError || !waitingUsers || waitingUsers.length === 0) {
      return new Response(JSON.stringify({
        error: 'No users found in this waiting room.',
      }), { status: 404 });
    }

    const totalUsers = waitingUsers.length;

    // STEP 3: Validate that the number of users is even.
    if (totalUsers % 2 !== 0) {
      return new Response(JSON.stringify({
        error: 'The number of participants must be even to create a league room.',
      }), { status: 400 });
    }

    // STEP 4: Create a new league room.
    const leagueRoomName = `New League Room - ${new Date().toISOString()}`;
    const { data: newLeagueRoom, error: leagueRoomError } = await supabase
      .from('league_rooms')
      .insert({ league_room_name: leagueRoomName })
      .select('league_room_id')
      .single();

    if (leagueRoomError || !newLeagueRoom) {
      return new Response(JSON.stringify({
        error: leagueRoomError?.message || 'Failed to create a league room.',
      }), { status: 400 });
    }

    const league_room_id = newLeagueRoom.league_room_id;

    // STEP 5: Assign this newly created league_room_id to all rows of this waiting_room_id.
    const { error: updateError } = await supabase
      .from('waiting_rooms')
      .update({ league_room_id })
      .eq('waiting_room_id', waiting_room_id)
      .is('league_room_id', null);

    if (updateError) {
      return new Response(JSON.stringify({ error: updateError.message }), {
        status: 400,
      });
    }

    // STEP 6: Randomly distribute users into teams of 2.
    const userIds = waitingUsers.map((user) => user.user_id);
    const shuffledUserIds = userIds.sort(() => 0.5 - Math.random());
    const teams = [];

    for (let i = 0; i < shuffledUserIds.length; i += 2) {
      teams.push([shuffledUserIds[i], shuffledUserIds[i + 1]]);
    }

    for (const team of teams) {
      const { error: createTeamError } = await supabase.functions.invoke(
        'create_team',
        { body: { user_ids: team, league_room_id } }
      );

      if (createTeamError) {
        return new Response(JSON.stringify({
          error: `Failed to create a team: ${createTeamError.message}`,
        }), { status: 400 });
      }
    }

    // Return success response.
    return new Response(JSON.stringify({
      message: 'League room and teams successfully created.',
      league_room_id,
      number_of_teams: teams.length,
    }), { status: 201 });
  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(JSON.stringify({
      error: 'Internal Server Error',
    }), { status: 500 });
  }
});
