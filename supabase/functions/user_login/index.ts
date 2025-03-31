import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "register_user" is up and running!`);

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
    let email: string;
    let password: string;
    try {
      const parsedBody = JSON.parse(bodyText);
      email = parsedBody.email;
      password = parsedBody.password;
    } catch (parseError) {
      console.error('JSON parsing error:', parseError);
      return new Response(
        JSON.stringify({ error: 'Invalid JSON format.' }),
        { status: 400 }
      );
    }

    console.log(`Parsed email: ${email}, password: ${password ? '*****' : 'No Password'}`);

    if (!email || !password) {
      console.log('Email or password not provided.');
      return new Response(
        JSON.stringify({ error: 'Email and password are required.' }),
        { status: 400 }
      );
    }
    if (typeof email !== 'string' || typeof password !== 'string') {
      console.warn('Invalid data types for email or password.');
      return new Response(
        JSON.stringify({ error: 'Invalid data types for email or password.' }),
        { status: 400 }
      );
    }
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    console.log('Supabase client initialized.');

    // emailk check
    const { data: existingUser, error: fetchError } = await supabase
      .from('users')
      .select('user_id, name, email')
      .eq('email', email)
      .eq('password', password)
      .maybeSingle();

    if (fetchError) {
      console.error(`Supabase error while fetching user: ${fetchError.message}`);
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 400,
      });
    }
    if (!existingUser) {
      console.warn(`User does not exists with email: ${email}`);
      return new Response(
        JSON.stringify({ error: 'User already exists with this email.' }),
        { status: 409 }
      );
    }
    const successResponse = {
      message: 'User found successfully.',
      id: existingUser.user_id,
      name: existingUser.name,
      email: existingUser.email,
    };
    console.log(`User found successfully: ${email}`);
    console.log(`Response: ${JSON.stringify(successResponse)}`);

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