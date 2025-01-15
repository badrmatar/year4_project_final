// supabase/functions/get_waiting_room_users/index.ts

import { serve } from 'https://deno.land/std@0.131.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Load environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const supabase = createClient(supabaseUrl, supabaseKey)

console.log(`Edge function "get_waiting_room_users" is running...`)

/*
  Expected incoming JSON:
  {
    "waiting_room_id": 123
  }

  Returns on success: 200 OK with an array of user objects, e.g.:
  [
    { "user_id": 1, "name": "Alice" },
    { "user_id": 2, "name": "Bob" }
  ]
*/

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
      })
    }

    const body = await req.json().catch(() => null)
    if (!body || typeof body.waiting_room_id !== 'number') {
      return new Response(
        JSON.stringify({ error: 'Invalid or missing "waiting_room_id".' }),
        { status: 400 }
      )
    }

    const waitingRoomId = body.waiting_room_id

    // Step 1: Find all rows in waiting_rooms for the given waiting_room_id
    const { data: waitingRoomRows, error: waitingRoomError } = await supabase
      .from('waiting_rooms')
      .select('user_id')
      .eq('waiting_room_id', waitingRoomId)

    if (waitingRoomError) {
      return new Response(JSON.stringify({ error: waitingRoomError.message }), {
        status: 400,
      })
    }

    if (!waitingRoomRows || waitingRoomRows.length === 0) {
      // No entries found for that waiting_room_id
      return new Response(JSON.stringify([]), { status: 200 })
    }

    // Step 2: Extract user_ids
    const userIds = waitingRoomRows.map((row) => row.user_id)

    // Step 3: Fetch user data from "users" table
    // Assuming you have a "name" column in "users"
    const { data: usersData, error: usersError } = await supabase
      .from('users')
      .select('user_id, name')
      .in('user_id', userIds)

    if (usersError) {
      return new Response(JSON.stringify({ error: usersError.message }), {
        status: 400,
      })
    }

    // Step 4: Return the list of user objects
    // e.g. [ { user_id: 1, name: "Alice" }, { user_id: 2, name: "Bob" } ]
    return new Response(JSON.stringify(usersData), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Unexpected error:', error)
    // Optionally differentiate dev vs. prod environment for more detail
    return new Response(
      JSON.stringify({ error: 'Internal Server Error' }),
      { status: 500 }
    )
  }
})
