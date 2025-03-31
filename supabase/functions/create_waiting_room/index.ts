import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "create_waiting_room" is up and running!`);

serve(async (req) => {
  try {
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
    try {
      const parsedBody = JSON.parse(bodyText);
      userId = parsedBody.userId;
    } catch (parseError) {
      console.error('JSON parsing error:', parseError);
      return new Response(
        JSON.stringify({ error: 'Invalid JSON format.' }),
        { status: 400 }
      );
    }

    console.log(`Parsed userId: ${userId}`);

    if (!userId) {
      console.log('User ID not provided.');
      return new Response(
        JSON.stringify({ error: 'User ID is required.' }),
        { status: 400 }
      );
    }

    if (typeof userId !== 'number') {
      console.warn('Invalid data type for userId.');
      return new Response(
        JSON.stringify({ error: 'Invalid data type for userId.' }),
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

    const { data: existingWaitingRoom, error: checkError } = await supabase
      .from('waiting_rooms')
      .select('waiting_room_id')
      .eq('user_id', userId)
      .is('league_room_id', null)
      .maybeSingle();

    if (checkError) {
      console.error(`Error checking existing waiting room: ${checkError.message}`);
      return new Response(JSON.stringify({ error: checkError.message }), {
        status: 400,
      });
    }

    if (existingWaitingRoom) {
      console.warn(`User already has an active waiting room: ${existingWaitingRoom.waiting_room_id}`);
      return new Response(
        JSON.stringify({
          error: 'User already has an active waiting room.',
          waiting_room_id: existingWaitingRoom.waiting_room_id
        }),
        { status: 409 }
      );
    }

    //   new waiting room
    const { data: newWaitingRoom, error: insertError } = await supabase
      .from('waiting_rooms')
      .insert([
        {
          user_id: userId,
          league_room_id: null
        }
      ])
      .select()
      .single();

    if (insertError) {
      console.error(`Error creating waiting room: ${insertError.message}`);
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 400,
      });
    }

    const successResponse = {
      message: 'Waiting room created successfully.',
      waiting_room_id: newWaitingRoom.waiting_room_id,
      created_at: newWaitingRoom.created_at
    };

    console.log(`Created waiting room: ${JSON.stringify(successResponse)}`);

    return new Response(
      JSON.stringify(successResponse),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 201,
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