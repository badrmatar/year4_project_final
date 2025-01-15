import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const supabase = createClient(supabaseUrl, supabaseKey);

console.log('Edge function "get_waiting_room_users" is running!');

/*
  Incoming JSON: { "waiting_room_id": 999 }

  Returns: an array like:
  [
    {
      "user_id": 1,
      "date_joined": "2025-01-11T10:00:00Z",
      "users": {
         "name": "Alice"
      }
    },
    {
      "user_id": 2,
      "date_joined": "2025-01-11T11:00:00Z",
      "users": {
         "name": "Bob"
      }
    }
  ]
*/

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
      });
    }

    const body = await req.json().catch(() => null);
    if (!body || typeof body.waiting_room_id !== 'number') {
      return new Response(
        JSON.stringify({ error: 'Invalid or missing "waiting_room_id".' }),
        { status: 400 }
      );
    }

    const waitingRoomId = body.waiting_room_id;

    // 1) Query waiting_rooms to get user_id, date_joined, plus a join on the "users" table
    //    so we can retrieve the user's name.
    const { data, error } = await supabase
      .from('waiting_rooms')
      .select(`
        user_id,
        created_at,
        users (
          name
        )
      `)
      .eq('waiting_room_id', waitingRoomId);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 400,
      });
    }

    // Return the array of records
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('Unexpected error:', err);
    return new Response(
      JSON.stringify({ error: 'Internal Server Error' }),
      { status: 500 }
    );
  }
});
