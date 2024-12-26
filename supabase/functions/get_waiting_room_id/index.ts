import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "get_waiting_room_id" is up and running!`);

serve(async (req) => {
  try {
    // Only allow POST requests
    if (req.method !== 'POST') {
      console.log(`Received non-POST request: ${req.method}`);
      return new Response(JSON.stringify({ error: 'Method Not Allowed' }), { status: 405 });
    }

    // Read the raw body for debugging
    const bodyText = await req.text();
    console.log(`Raw request body: ${bodyText}`);

    if (bodyText.trim() === '') {
      console.warn('Empty request body received.');
      return new Response(
        JSON.stringify({ error: 'Request body cannot be empty.' }),
        { status: 400 }
      );
    }

    // Parse the request body
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

    // Validate data type
    if (typeof userId !== 'number') {
      console.warn('Invalid data type for userId.');
      return new Response(
        JSON.stringify({ error: 'Invalid data type for userId.' }),
        { status: 400 }
      );
    }

    // Initialize Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    console.log('Supabase client initialized.');

    // First check if the user exists
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

    // Check for existing waiting room with null league_room_id
    const { data: existingWaitingRoom, error: fetchError } = await supabase
      .from('waiting_rooms')
      .select('waiting_room_id')
      .eq('user_id', userId)
      .is('league_room_id', null)
      .maybeSingle();

    if (fetchError) {
      console.error(`Supabase error while fetching waiting room: ${fetchError.message}`);
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 400,
      });
    }

    if (existingWaitingRoom) {
      // Return existing waiting room id
      const successResponse = {
        message: 'Existing waiting room found.',
        waiting_room_id: existingWaitingRoom.waiting_room_id
      };
      console.log(`Found existing waiting room: ${JSON.stringify(successResponse)}`);
      
      return new Response(
        JSON.stringify(successResponse),
        {
          headers: { 'Content-Type': 'application/json' },
          status: 200,
        }
      );
    }

    // If no waiting room with null league_room_id exists, get the latest waiting room for this user
    const { data: latestWaitingRoom, error: latestError } = await supabase
      .from('waiting_rooms')
      .select('waiting_room_id')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (latestError) {
      console.error(`Supabase error while fetching latest waiting room: ${latestError.message}`);
      return new Response(JSON.stringify({ error: latestError.message }), {
        status: 400,
      });
    }

    const successResponse = {
      message: latestWaitingRoom ? 'Latest waiting room found.' : 'No waiting room found.',
      waiting_room_id: latestWaitingRoom ? latestWaitingRoom.waiting_room_id : null
    };
    
    console.log(`Response: ${JSON.stringify(successResponse)}`);

    return new Response(
      JSON.stringify(successResponse),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 200,
      }
    );

  } catch (error) {
    console.error('Unexpected error:', error);

    // Determine the environment
    const environment = Deno.env.get('ENVIRONMENT') || 'production';
    const isDevelopment = environment === 'development';

    // Prepare the error response
    let errorMessage = 'Internal Server Error';
    if (isDevelopment) {
      // Safely extract the error message
      const errorDetails = error instanceof Error ? error.message : String(error);
      errorMessage = `Internal Server Error: ${errorDetails}`;
    }

    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});