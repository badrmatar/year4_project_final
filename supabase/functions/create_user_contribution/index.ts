import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body: any;
  try {
    body = await req.json();
  } catch (error) {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Extract and validate parameters
  const { user_id, start_time, start_latitude, start_longitude, distance_covered } = body;

    // remove distance_covered
  const validationErrors = [];
  if (typeof user_id !== 'number') validationErrors.push('user_id must be a number');
  if (typeof start_time !== 'string') validationErrors.push('start_time must be a string (ISO 8601)');
  if (typeof start_latitude !== 'number') validationErrors.push('start_latitude must be a number');
  if (typeof start_longitude !== 'number') validationErrors.push('start_longitude must be a number');
  if (typeof distance_covered !== 'number') validationErrors.push('distance_covered must be a number');

  if (validationErrors.length > 0) {
    return new Response(
      JSON.stringify({ error: 'Invalid parameters', details: validationErrors }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  try {
    // Step 1: Get the active team_challenge_id for the user
    const { data: teamMembership, error: teamError } = await supabase
      .from('team_memberships')
      .select('team_id')
      .eq('user_id', user_id)
      .is('date_left', null)
      .single();

    if (teamError || !teamMembership) {
      return new Response(
        JSON.stringify({ error: 'User is not part of any active team.' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const team_id = teamMembership.team_id;

    const { data: activeChallenge, error: challengeError } = await supabase
      .from('team_challenges')
      .select('team_challenge_id')
      .eq('team_id', team_id)
      .eq('iscompleted', false)
      .maybeSingle();

    if (challengeError) {
      return new Response(
        JSON.stringify({ error: 'Error fetching active team challenge.' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!activeChallenge) {
      return new Response(
        JSON.stringify({ error: 'No active team challenge found for this team.' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const team_challenge_id = activeChallenge.team_challenge_id;

    // Step 2: Insert user contribution
    const end_time = new Date().toISOString();

    const { data, error } = await supabase
      .from('user_contributions')
      .insert({
        team_challenge_id,
        user_id,
        start_time,
        end_time,
        start_latitude,
        end_latitude: start_latitude, // Assuming same as start for now
        start_longitude,
        end_longitude: start_longitude,
        active: false,
        contribution_details: `Distance covered: ${distance_covered}`, // Add meaningful details
        distance_covered: Number(distance_covered),
      })
      .select()
      .single();

    if (error) {
      return new Response(
        JSON.stringify({ error: 'Failed to insert user contribution.', details: error.message }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Success response
    return new Response(JSON.stringify({ data }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('Unexpected error:', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: err.message }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
});
