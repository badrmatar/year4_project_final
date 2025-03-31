import { serve } from 'https://deno.land/std@0.131.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

console.log(`Function "register_user" is up and running!`);

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method Not Allowed' }), { status: 405 });
    }

    const bodyText = await req.text();
    if (bodyText.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'Request body cannot be empty.' }),
        { status: 400 }
      );
    }

    let email: string;
    let password: string;
    let username: string;
    try {
      const parsedBody = JSON.parse(bodyText);
      email = parsedBody.email;
      password = parsedBody.password;
      username = parsedBody.username;
    } catch (parseError) {
      return new Response(
        JSON.stringify({ error: 'Invalid JSON format.' }),
        { status: 400 }
      );
    }

    if (!email || !password || !username) {
      return new Response(
        JSON.stringify({ error: 'Email, password and username are required.' }),
        { status: 400 }
      );
    }

    if (typeof email !== 'string' || typeof password !== 'string' || typeof username !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Invalid data types provided.' }),
        { status: 400 }
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { data: existingUser, error: fetchError } = await supabase
      .from('users')
      .select('email')
      .eq('email', email)
      .maybeSingle();

    if (fetchError) {
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 400,
      });
    }

    if (existingUser) {
      return new Response(
        JSON.stringify({ error: 'User already exists with this email.' }),
        { status: 409 }
      );
    }

    const { data, error: insertError } = await supabase
      .from('users')
      .insert([
        {
          email: email,
          password: password,
          name: username
        },
      ]);

    if (insertError) {
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 400,
      });
    }

    const successResponse = {
      message: 'User registered successfully.',
      email: email,
      username: username
    };

    return new Response(
      JSON.stringify(successResponse),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 201,
      }
    );
  } catch (error) {
    const environment = Deno.env.get('ENVIRONMENT') || 'production';
    const isDevelopment = environment === 'development';
    const errorMessage = isDevelopment && error instanceof Error ?
      `Internal Server Error: ${error.message}` :
      'Internal Server Error';

    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});