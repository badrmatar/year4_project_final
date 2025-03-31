import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "get_active_league_room" is up and running!`);

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      console.log(`Received non-POST request: ${req.method}`);
      return new Response(JSON.stringify({ error: 'Method Not Allowed' }), {
        status: 405,
      });
    }
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
    if (typeof userId !== 'number') {
      return new Response(
        JSON.stringify({ error: 'user_id must be a number.' }),
        { status: 400 }
      );
    }
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

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
    const { data: waitingRoomData, error: waitingRoomError } = await supabase
      .from('waiting_rooms')
      .select(`
        waiting_room_id,
        league_room_id,
        league_rooms (
          league_room_id,
          created_at,
          ended_at
        )
      `)
      .eq('user_id', userId)
      .not('league_room_id', 'is', null)
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    if (waitingRoomError?.code === 'PGRST116') {
      return new Response(JSON.stringify({
        message: 'No active league room found.',
        league_room_id: null
      }), { status: 200 });
    }

    if (waitingRoomError) {
      return new Response(JSON.stringify({ error: waitingRoomError.message }), {
        status: 400
      });
    }

    if (waitingRoomData.league_rooms.ended_at !== null) {
      return new Response(JSON.stringify({
        message: 'No active league room found.',
        league_room_id: null
      }), { status: 200 });
    }
    return new Response(JSON.stringify({
      message: 'Active league room found.',
      league_room_id: waitingRoomData.league_room_id,
      waiting_room_id: waitingRoomData.waiting_room_id,
      created_at: waitingRoomData.league_rooms.created_at,
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Unexpected error:', error);

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