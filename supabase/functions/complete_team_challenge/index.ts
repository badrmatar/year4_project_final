import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

serve(async (req: Request) => {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      },
    );
  }

  // Attempt to parse JSON body
  let body;
  try {
    body = await req.json();
  } catch (_err) {
    return new Response(
      JSON.stringify({ error: 'Invalid JSON body' }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      },
    );
  }

  // Destructure fields from request body
  const {
    user_id,
    start_time,
    end_time,
    start_latitude,
    start_longitude,
    end_latitude,
    end_longitude,
    distance_covered,
  } = body;

  // Validate required fields
  const validationErrors = [];
  if (typeof user_id !== 'number') {
    validationErrors.push('user_id must be a number');
  }
  if (typeof start_time !== 'string') {
    validationErrors.push('start_time must be a string (ISO 8601 format)');
  }
  if (typeof start_latitude !== 'number') {
    validationErrors.push('start_latitude must be a number');
  }
  if (typeof start_longitude !== 'number') {
    validationErrors.push('start_longitude must be a number');
  }
  if (typeof end_latitude !== 'number') {
    validationErrors.push('end_latitude must be a number');
  }
  if (typeof end_longitude !== 'number') {
    validationErrors.push('end_longitude must be a number');
  }
  if (typeof distance_covered !== 'number') {
    validationErrors.push('distance_covered must be a number');
  }

  if (validationErrors.length > 0) {
    return new Response(
      JSON.stringify({ error: 'Invalid parameters', details: validationErrors }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      },
    );
  }

  try {
    // Step 1: Get active team with proper error handling
    const { data: teamMembership, error: teamError } = await supabase
      .from('team_memberships')
      .select('team_id')
      .eq('user_id', user_id)
      .is('date_left', null)
      .single();

    if (teamError) {
      return new Response(
        JSON.stringify({
          error: 'Error finding team membership',
          details: teamError.message
        }),
        { status: 400 }
      );
    }

    // Step 2: Get latest active challenge
    const { data: activeChallenge, error: challengeError } = await supabase
      .from('team_challenges')
      .select('team_challenge_id')
      .eq('team_id', teamMembership.team_id)
      .eq('iscompleted', false)
      .order('team_challenge_id', { ascending: false })
      .limit(1)
      .single();

    if (challengeError) {
      return new Response(
        JSON.stringify({
          error: 'Error fetching active team challenge.',
          details: challengeError.message
        }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      );
    }

    if (!activeChallenge) {
      return new Response(
        JSON.stringify({
          error: 'No active team challenge found for this team.',
        }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        },
      );
    }

    // 3) Insert user contribution
    const team_challenge_id = activeChallenge.team_challenge_id;
    const finalEndTime = end_time ?? new Date().toISOString();

    const { data: contributionData, error: contributionError } = await supabase
      .from('user_contributions')
      .insert({
        team_challenge_id,
        user_id,
        start_time,
        end_time: finalEndTime,
        start_latitude,
        end_latitude,
        start_longitude,
        end_longitude,
        active: false,
        contribution_details: `Distance covered: ${distance_covered}`,
        distance_covered: distance_covered,
      })
      .select('*')
      .single();

    if (contributionError) {
      return new Response(
        JSON.stringify({
          error: 'Failed to insert user contribution.',
          details: contributionError.message,
        }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        },
      );
    }

    // Get challenge details and total team distance
    const { data: challengeData, error: challengeError2 } = await supabase
      .from('team_challenges')
      .select(`
        challenge_id,
        challenges (length),
        user_contributions (distance_covered)
      `)
      .eq('team_challenge_id', team_challenge_id)
      .single();

    if (challengeError2) {
      return new Response(
        JSON.stringify({
          error: 'Error getting challenge details',
          details: challengeError2.message,
        }),
        { status: 500 }
      );
    }

    // Calculate total distance covered by the team
    const contributions = challengeData.user_contributions || [];
    const totalDistanceInMeters = contributions.reduce(
      (sum: number, contrib: any) => sum + (contrib.distance_covered || 0),
      0
    );
    const totalDistanceInKm = totalDistanceInMeters / 1000;

    // Check if challenge distance has been met
    const requiredDistance = challengeData.challenges.length;
    let challengeCompleted = false;

    if (totalDistanceInKm >= requiredDistance) {
      // Update team_challenge as completed
      const { error: updateError } = await supabase
        .from('team_challenges')
        .update({ iscompleted: true })
        .eq('team_challenge_id', team_challenge_id);

      if (updateError) {
        return new Response(
          JSON.stringify({
            error: 'Error updating challenge completion status',
            details: updateError.message,
          }),
          { status: 500 }
        );
      }
      challengeCompleted = true;
    }

    // Return success with team_challenge_id and completion status
    return new Response(
      JSON.stringify({
        data: {
          ...contributionData,
          team_challenge_id,
          challenge_completed: challengeCompleted,
          total_distance_km: totalDistanceInKm,
          required_distance_km: requiredDistance
        }
      }),
      {
        status: 201,
        headers: { 'Content-Type': 'application/json' },
      },
    );

  } catch (err) {
    console.error('Unexpected error:', err);
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        details: err.message,
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      },
    );
  }
});