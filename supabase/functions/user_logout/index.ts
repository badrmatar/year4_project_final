import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "user_logout" is up and running!`);

serve(async (req) => {
  try {
    // Only allow POST requests
    if (req.method !== 'POST') {
      console.log(`Received non-POST request: ${req.method}`);
      return new Response(JSON.stringify({ error: 'Method Not Allowed' }), { status: 405 });
    }

    // Read the raw body
    const bodyText = await req.text();
    console.log(`Raw request body: ${bodyText}`);

    if (!bodyText.trim()) {
      console.warn('Empty request body received.');
      return new Response(JSON.stringify({ error: 'Request body cannot be empty.' }), {
        status: 400,
      });
    }

    // Parse JSON
    let userId: number;
    try {
      const parsedBody = JSON.parse(bodyText);
      userId = parsedBody.user_id;
    } catch (error) {
      console.error('JSON parsing error:', error);
      return new Response(JSON.stringify({ error: 'Invalid JSON format.' }), { status: 400 });
    }

    console.log(`Parsed user_id: ${userId}`);

    if (!userId || typeof userId !== 'number') {
      console.log('Invalid or missing user_id.');
      return new Response(JSON.stringify({ error: 'Invalid or missing user_id.' }), {
        status: 400,
      });
    }

    // ----------------------------------------------------------
    // Since you have no 'auth.sessions' table, we just
    // return success here. If you wanted to track login state
    // in your 'users' table, you could do that below.
    // ----------------------------------------------------------

    /*
    // Example (optional):
    // Mark user as logged out in your 'users' table:
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { error: updateError } = await supabase
      .from('users')
      .update({ active_session: false })
      .eq('user_id', userId);

    if (updateError) {
      console.error(`Error updating user session: ${updateError.message}`);
      return new Response(JSON.stringify({ error: updateError.message }), { status: 400 });
    }
    */

    console.log(`User with ID ${userId} "logged out" (dummy).`);
    const successResponse = {
      message: 'User logged out successfully (no server session).',
    };

    return new Response(JSON.stringify(successResponse), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error) {
    console.error('Unexpected error:', error);

    return new Response(
      JSON.stringify({ error: 'Internal Server Error' }),
      { status: 500 }
    );
  }
});
