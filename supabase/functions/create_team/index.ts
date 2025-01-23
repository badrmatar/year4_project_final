import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Environment Variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)

serve(async (req: Request) => {
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
      return new Response(JSON.stringify({ error: 'Invalid JSON body' }), { status: 400 })
    }

    const { user_ids, league_room_id } = body
    console.log(`create_team: user_ids=${user_ids}, league_room_id=${league_room_id}`)

    // Validate input
    if (!Array.isArray(user_ids) || user_ids.length === 0 || !user_ids.every(id => typeof id === 'number')) {
      return new Response(JSON.stringify({ error: 'user_ids must be a non-empty array of numbers' }), { status: 400 })
    }

    if (typeof league_room_id !== 'number') {
      return new Response(JSON.stringify({ error: 'league_room_id must be a number' }), { status: 400 })
    }

    // Validate that the league_room_id exists
    const { data: leagueRoomData, error: leagueRoomError } = await supabase
      .from('league_rooms')
      .select('league_room_id')
      .eq('league_room_id', league_room_id)
      .single()

    if (leagueRoomError || !leagueRoomData) {
      console.error(`create_team: Invalid league_room_id = ${league_room_id}`)
      return new Response(
        JSON.stringify({ error: 'Invalid league_room_id. League room not found.' }),
        { status: 400 }
      )
    }

    // Fetch user names from the database
    const { data: usersData, error: usersError } = await supabase
      .from('users')
      .select('user_id, name')
      .in('user_id', user_ids)

    if (usersError) {
      console.error(`create_team: Error fetching users: ${usersError.message}`)
      return new Response(JSON.stringify({ error: usersError.message }), { status: 400 })
    }

    // Check if all requested users exist
    if (!usersData || usersData.length !== user_ids.length) {
      console.error(`create_team: Some user_ids are invalid. Provided: ${user_ids}`)
      return new Response(JSON.stringify({ error: 'One or more user_ids are invalid' }), { status: 400 })
    }

    // Construct team_name by joining user names
    const names = usersData.map(u => u.name)
    const team_name = names.join(' & ')

    // Insert a new team with league_room_id
    const { data: teamData, error: teamError } = await supabase
      .from('teams')
      .insert({ team_name, league_room_id })
      .select('team_id')
      .single()

    if (teamError || !teamData) {
      console.error(`create_team: Error inserting team: ${teamError?.message}`)
      return new Response(JSON.stringify({ error: teamError?.message }), { status: 400 })
    }

    const team_id = teamData.team_id

    // Insert memberships
    const dateJoined = new Date().toISOString().split('T')[0]
    const memberships = user_ids.map(uid => ({
      team_id,
      user_id: uid,
      date_joined: dateJoined
    }))

    const { error: membershipError } = await supabase
      .from('team_memberships')
      .insert(memberships)

    if (membershipError) {
      console.error(`create_team: Error inserting memberships: ${membershipError.message}`)
      return new Response(JSON.stringify({ error: membershipError.message }), { status: 400 })
    }

    console.log(
      `create_team: Successfully created team_id=${team_id} with user_ids=[${user_ids}] in league_room_id=${league_room_id}`
    )
    return new Response(
      JSON.stringify({
        team_id,
        team_name,
        league_room_id,
        members: user_ids
      }),
      { status: 201 }
    )
  } catch (error) {
    console.error('create_team: Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal Server Error' }),
      { status: 500 }
    )
  }
})
