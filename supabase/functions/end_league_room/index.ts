// supabase/functions/end_league_room/index.ts

import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Load environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// Create Supabase client using the service role key
const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req: Request) => {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Parse the request body
  let body: any;
  try {
    body = await req.json();
  } catch (error) {
    return new Response(
      JSON.stringify({ error: 'Invalid JSON body' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Expect a league_room_id in the body
  const { league_room_id } = body;
  if (typeof league_room_id !== 'number') {
    return new Response(
      JSON.stringify({ error: 'league_room_id must be a number' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Fetch the league room record
  const { data: leagueRoomData, error: fetchError } = await supabase
    .from('league_rooms')
    .select('league_room_id, created_at, ended_at')
    .eq('league_room_id', league_room_id)
    .maybeSingle();

  if (fetchError) {
    return new Response(
      JSON.stringify({ error: fetchError.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

  if (!leagueRoomData) {
    return new Response(
      JSON.stringify({ error: 'League room not found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // If the league room is already ended, return early.
  if (leagueRoomData.ended_at !== null) {
    return new Response(
      JSON.stringify({ message: 'League room already ended' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Set the current time as now
  const now = new Date();

  // Update the league room record: set ended_at to the current time
  const { data: updatedLeagueData, error: updateError } = await supabase
    .from('league_rooms')
    .update({ ended_at: now.toISOString() })
    .eq('league_room_id', league_room_id)
    .select();

  if (updateError) {
    return new Response(
      JSON.stringify({ error: updateError.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Fetch the teams associated with this league room
  const { data: teamsData, error: teamsError } = await supabase
    .from('teams')
    .select('team_id')
    .eq('league_room_id', league_room_id);

  if (teamsError) {
    return new Response(
      JSON.stringify({ error: teamsError.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // If teams exist, update their memberships with date_left = now (using only the date portion)
  if (teamsData && teamsData.length > 0) {
    const teamIds = teamsData.map((team) => team.team_id);
    const { error: updateMembershipError } = await supabase
      .from('team_memberships')
      .update({ date_left: now.toISOString().split('T')[0] }) // store date part only
      .in('team_id', teamIds);

    if (updateMembershipError) {
      return new Response(
        JSON.stringify({ error: updateMembershipError.message }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }
  }

  return new Response(
    JSON.stringify({
      message: 'League room ended successfully and team memberships updated with date_left.',
      leagueRoom: updatedLeagueData,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
});
