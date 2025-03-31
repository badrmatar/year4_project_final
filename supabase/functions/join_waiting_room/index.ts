import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "join_waiting_room" is up and running!`);

serve(async (req) => {
  try {
    // Only allow POST requests
    if (req.method !== 'POST') {
      console.log(`Received non-POST request: ${req.method}`);
      return new Response(JSON.stringify({ error: 'Method Not Allowed' }), { status: 405 });
    }
    const bodyText = await req.text();
    console.log(`Raw request body: ${bodyText}`);

    if (bodyText.trim() === '') {
      console.warn('Empty request body received.');
      return new Response(
        JSON.stringify({ error: 'Request body cannot be empty.' }),
        { status: 400 }
      );
    }
    let userId: number;
    let waitingRoomId: number;
    try {
      const parsedBody = JSON.parse(bodyText);
      userId = parsedBody.userId;
      waitingRoomId = parsedBody.waitingRoomId;
    } catch (parseError) {
      console.error('JSON parsing error:', parseError);
      return new Response(
        JSON.stringify({ error: 'Invalid JSON format.' }),
        { status: 400 }
      );
    }

    console.log(`Parsed userId: ${userId}, waitingRoomId: ${waitingRoomId}`);
    if (!userId || !waitingRoomId) {
      console.log('Missing required fields.');
      return new Response(
        JSON.stringify({ error: 'User ID and waiting room ID are required.' }),
        { status: 400 }
      );
    }
    if (typeof userId !== 'number' || typeof waitingRoomId !== 'number') {
      console.warn('Invalid data types for userId or waitingRoomId.');
      return new Response(
        JSON.stringify({ error: 'Invalid data types for userId or waitingRoomId.' }),
        { status: 400 }
      );
    }
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    console.log('Supabase client initialized.');

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
        JSON.stringify({ 
          error: 'User not found.',
          status: 'USER_NOT_FOUND'
        }),
        { status: 404 }
      );
    }
    const { data: waitingRoom, error: waitingRoomError } = await supabase
      .from('waiting_rooms')
      .select('*')
      .eq('waiting_room_id', waitingRoomId)
      .is('league_room_id', null)
      .limit(1)
      .maybeSingle();

    if (waitingRoomError) {
      console.error(`Error checking waiting room: ${waitingRoomError.message}`);
      return new Response(JSON.stringify({ error: waitingRoomError.message }), {
        status: 400,
      });
    }

    if (!waitingRoom) {
      console.warn(`Active waiting room not found with ID: ${waitingRoomId}`);
      return new Response(
        JSON.stringify({
          error: 'Active waiting room not found.',
          status: 'WAITING_ROOM_NOT_FOUND'
        }),
        { status: 404 }
      );
    }
    const { data: existingParticipant, error: checkError } = await supabase
      .from('waiting_rooms')
      .select('waiting_room_id')
      .eq('waiting_room_id', waitingRoomId)
      .eq('user_id', userId)
      .is('league_room_id', null)
      .maybeSingle();

    if (checkError) {
      console.error(`Error checking existing participant: ${checkError.message}`);
      return new Response(JSON.stringify({ error: checkError.message }), {
        status: 400,
      });
    }

    if (existingParticipant) {
      console.warn(`User ${userId} is already in waiting room ${waitingRoomId}`);
      return new Response(
        JSON.stringify({
          error: 'User is already in this waiting room.',
          status: 'ALREADY_IN_WAITING_ROOM',
          waiting_room_id: waitingRoomId
        }),
        { status: 409 }
      );
    }

    // Add user
    const { data: newParticipant, error: insertError } = await supabase
      .from('waiting_rooms')
      .insert([
        {
          waiting_room_id: waitingRoomId,
          user_id: userId,
          league_room_id: null
        }
      ])
      .select()
      .single();

    if (insertError) {
      console.error(`Error adding user to waiting room: ${insertError.message}`);
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 400,
      });
    }

    const successResponse = {
      message: 'Successfully joined waiting room.',
      waiting_room_id: waitingRoomId,
      created_at: newParticipant.created_at
    };

    console.log(`User joined waiting room: ${JSON.stringify(successResponse)}`);

    return new Response(
      JSON.stringify(successResponse),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 200,
      }
    );

  } catch (error) {
    console.error('Unexpected error:', error);

    const environment = Deno.env.get('ENVIRONMENT') || 'production';
    const isDevelopment = environment === 'development';

    let errorMessage = 'Internal Server Error';
    if (isDevelopment) {
      const errorDetails = error instanceof Error ? error.message : String(error);
      errorMessage = `Internal Server Error: ${errorDetails}`;
    }

    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});