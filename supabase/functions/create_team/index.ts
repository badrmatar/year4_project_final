import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      console.log(`create_team: Invalid method = ${req.method}`)
      return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 })
    }

    const bodyText = await req.text()
    console.log(`create_team: Raw request body: ${bodyText}`)

    let body: any
    try {
      body = JSON.parse(bodyText)
    } catch (error) {
      console.error('create_team: JSON parsing error:', error)
      return new Response(JSON.stringify({ error: 'Invalid JSON body' }), { status: 400 })
    }

    const { user_ids, league_room_id } = body
    console.log(`create_team: Processing request for user_ids=${JSON.stringify(user_ids)}, league_room_id=${league_room_id}`)

    if (!Array.isArray(user_ids) || user_ids.length === 0 || !user_ids.every(id => typeof id === 'number')) {
      console.error('create_team: Invalid user_ids:', user_ids)
      return new Response(JSON.stringify({ error: 'user_ids must be a non-empty array of numbers' }), { status: 400 })
    }

    if (typeof league_room_id !== 'number') {
      console.error('create_team: Invalid league_room_id:', league_room_id)
      return new Response(JSON.stringify({ error: 'league_room_id must be a number' }), { status: 400 })
    }
    const { data: leagueRoom, error: leagueRoomError } = await supabase
      .from('league_rooms')
      .select('*')
      .eq('league_room_id', league_room_id)
      .single();

    if (leagueRoomError || !leagueRoom) {
      console.error('create_team: League room error:', leagueRoomError)
      return new Response(JSON.stringify({ error: 'League room error: ' + leagueRoomError?.message }), { status: 400 })
    }

    if (leagueRoom.ended_at) {
      console.error('create_team: League room has ended:', league_room_id)
      return new Response(JSON.stringify({ error: 'League room has already ended' }), { status: 400 })
    }

    // get users
    const { data: usersData, error: usersError } = await supabase
      .from('users')
      .select('user_id, name')
      .in('user_id', user_ids);

    if (usersError || !usersData) {
      console.error('create_team: Error fetching users:', usersError)
      return new Response(JSON.stringify({ error: 'Error fetching users' }), { status: 400 })
    }

    // unique team nam by timestamp
    const timestamp = new Date().getTime();
    const team_name = `${usersData.map(u => u.name).join(' & ')} - ${timestamp}`;
    console.log('create_team: Creating team with name:', team_name);

    // Insert team
    const { data: newTeam, error: teamError } = await supabase
      .from('teams')
      .insert({ team_name, league_room_id })
      .select()
      .single();

    if (teamError || !newTeam) {
      console.error('create_team: Error creating team:', teamError)
      return new Response(JSON.stringify({ error: 'Error creating team: ' + teamError?.message }), { status: 400 })
    }

    // new memberships
    const dateJoined = new Date().toISOString().split('T')[0];
    const memberships = user_ids.map(uid => ({
      team_id: newTeam.team_id,
      user_id: uid,
      date_joined: dateJoined,
      date_left: null
    }));

    const { error: membershipError } = await supabase
      .from('team_memberships')
      .insert(memberships);

    if (membershipError) {
      console.error('create_team: Error creating memberships:', membershipError)
      return new Response(JSON.stringify({ error: 'Error creating memberships: ' + membershipError.message }), { status: 400 })
    }

    console.log('create_team: Successfully created team and memberships');
    return new Response(
      JSON.stringify({
        team_id: newTeam.team_id,
        team_name,
        league_room_id,
        members: user_ids
      }),
      { status: 201 }
    )

  } catch (error) {
    console.error('create_team: Unexpected error:', error)
    return new Response(JSON.stringify({
      error: 'Internal Server Error',
      details: error instanceof Error ? error.message : String(error)
    }), { status: 500 })
  }
});