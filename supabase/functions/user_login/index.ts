import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as bcrypt from 'https://deno.land/x/bcrypt@v0.4.1/mod.ts';

console.log(`Function "user_login" is up and running!`);

serve(async (req) => {
  try {
    // Parse the request body
    const { email, password } = await req.json();

    if (!email || !password) {
      return new Response(
        JSON.stringify({ error: 'Email and password are required.' }),
        { status: 400 }
      );
    }

    // Initialize Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    console.log(supabaseUrl);
    console.log(supabaseKey);
    const supabase = createClient(supabaseUrl, supabaseKey);
    console.log('Supabase client initialized.');
    // Query the users table for the provided email
    const { data: user, error } = await supabase
      .from('users')
      .select('id, email, password')
      .eq('email', email)
      .maybeSingle();

    console.log(`user --> ${user}, error --> ${error}`);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 400,
      });
    }

    if (!user) {
      return new Response(
        JSON.stringify({ error: 'Invalid email or password.' }),
        { status: 401 }
      );
    }

    // Compare the provided password with the stored hash
    const passwordMatch = await bcrypt.compare(password, user.password);

    if (!passwordMatch) {
      return new Response(
        JSON.stringify({ error: 'Invalid email or password.' }),
        { status: 401 }
      );
    }

    // Authentication successful
    return new Response(
      JSON.stringify({
        message: 'Authentication successful.',
        user_id: user.id,
        email: user.email,
        // Include any other user data as needed, excluding sensitive information
      }),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 200,
      }
    );
  }catch (error) {
       console.error('Unexpected error:', error);

       // Determine the environment
       const environment = Deno.env.get('ENVIRONMENT') || 'production';
       const isDevelopment = environment === 'development';

       // Prepare the error response
       let errorMessage = 'Internal Server Error';
       if (isDevelopment) {
         // Safely extract the error message
         const errorDetails = error instanceof Error ? error.message : String(error);
         errorMessage = Internal Server Error: ${errorDetails};
       }

       return new Response(JSON.stringify({ error: errorMessage }), {
         status: 500,
         headers: { 'Content-Type': 'application/json' },
       });
     }
});