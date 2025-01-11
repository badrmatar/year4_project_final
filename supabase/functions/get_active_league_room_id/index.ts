import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "get_active_league_room" is up and running!`);

serve(async (req) => {
  try {
    // Only allow POST requests
    if (req.method !== 'POST') {
      console.log(`Received non-POST request: ${req.method}`);
      return new Response(JSON.stringify({ error: 'Method Not Allowed' }), {
        status: 405,
      });
    }

    // Parse the request body
    const bodyText = await req.text();
    if (bodyText.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'Request body cannot be empty.' }),
        { status: 400 }
      );
    }

    let userId: number;
    try {
      const parsedBody = JSON.parse(bodyText);
      userId = parsedBody.user_id;
    } catch (parseError) {
      console.error('JSON parsing error:', parseError);
      return new Response(
        JSON.stringify({ error: 'Invalid JSON format.' }),
        { status: 400 }
      );
    }

    // Validate that userId is a number
    if (typeof userId !== 'number') {
      return new Response(
        JSON.stringify({ error: 'user_id must be a number.' }),
        { status: 400 }
      );
    }

    // Initialize Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 1) Confirm the user exists (optional, but recommended)
    const { data: existingUser, error: userError } = await supabase
      .from('users')
      .select('user_id')
      .eq('user_id', userId)
      .maybeSingle();

    if (userError) {
      console.error(`Supabase error while checking user: ${userError.message}`);
      return new Response(JSON.stringify({ error: userError.message }), {
        status: 400,
      });
    }

    if (!existingUser) {
      console.warn(`User not found with ID: ${userId}`);
      return new Response(
        JSON.stringify({ error: 'User not found.' }),
        { status: 404 }
      );
    }

    // 2) Calculate timestamp for 7 days ago
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();

    // 3) We want to find a record in "waiting_rooms" where:
    //    - user_id = {userId}
    //    - league_room_id is NOT null
    //    - league_rooms.created_at >= sevenDaysAgo (means league room is active)
    //
    //    We'll join "league_rooms" in the select to filter on created_at.

    const { data: activeRecord, error: fetchError } = await supabase
      .from('waiting_rooms')
      .select(`
        waiting_room_id,
        league_room_id,
        league_rooms (
          league_room_id,
          created_at
        )
      `)
      .eq('user_id', userId)
      .not('league_room_id', 'is', null)         // league_room_id != NULL
      .gte('league_rooms.created_at', sevenDaysAgo) // within the last 7 days
      .limit(1)
      .maybeSingle();

    if (fetchError) {
      console.error(`Supabase error while fetching active league room: ${fetchError.message}`);
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 400,
      });
    }

    // 4) Check if anything was found
    if (!activeRecord) {
      // No active league room found
      const noRoomResponse = {
        message: 'No active league room found for this user within the last 7 days.',
        league_room_id: null,
      };
      console.log(`Response: ${JSON.stringify(noRoomResponse)}`);
      return new Response(JSON.stringify(noRoomResponse), {
        headers: { 'Content-Type': 'application/json' },
        status: 200,
      });
    }

    // 5) Return the found league_room_id + waiting_room_id
    const successResponse = {
      message: 'Active league room found.',
      waiting_room_id: activeRecord.waiting_room_id,
      league_room_id: activeRecord.league_room_id,
      created_at: activeRecord.league_rooms.created_at,
    };
    console.log(`Response: ${JSON.stringify(successResponse)}`);

    return new Response(JSON.stringify(successResponse), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });

  } catch (error) {
    console.error('Unexpected error:', error);

    // Differentiate between dev/production for error detail
    const environment = Deno.env.get('ENVIRONMENT') || 'production';
    const isDevelopment = environment === 'development';
    let errorMessage = 'Internal Server Error';
    if (isDevelopment && error instanceof Error) {
      errorMessage = `Internal Server Error: ${error.message}`;
    }

    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
