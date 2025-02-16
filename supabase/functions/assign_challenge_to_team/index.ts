import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Load environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req: Request) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
      });
    }

    const body = await req.json();
    const { user_id, challenge_id } = body;

    // Validate input
    if (typeof user_id !== 'number' || typeof challenge_id !== 'number') {
      return new Response(
        JSON.stringify({ error: 'Invalid input. user_id and challenge_id must be numbers.' }),
        { status: 400 }
      );
    }

    // Check if user exists
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('user_id')
      .eq('user_id', user_id)
      .single();

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'User not found.' }),
        { status: 404 }
      );
    }

    // Check if user is in a team
    const { data: teamMembership, error: teamError } = await supabase
      .from('team_memberships')
      .select('team_id')
      .eq('user_id', user_id)
      .is('date_left', null)
      .single();

    if (teamError || !teamMembership) {
      return new Response(
        JSON.stringify({ error: 'User is not part of any active team.' }),
        { status: 400 }
      );
    }

    const team_id = teamMembership.team_id;

    // Check if another team has already picked the challenge and it's still active
    const { data: conflictingChallenge, error: conflictError } = await supabase
      .from('team_challenges')
      .select('team_challenge_id')
      .eq('challenge_id', challenge_id)
      .eq('iscompleted', false)
      .maybeSingle();

    if (conflictError) {
      return new Response(
        JSON.stringify({ error: 'Error checking active challenges for the same challenge.' }),
        { status: 500 }
      );
    }

    if (conflictingChallenge) {
      return new Response(
        JSON.stringify({
          error: 'This challenge has already been picked by another team and is still active.',
        }),
        { status: 400 }
      );
    }

    // Check if a team_challenge for the same team and challenge already exists
    const { data: existingChallenge, error: challengeError } = await supabase
      .from('team_challenges')
      .select('team_challenge_id')
      .eq('team_id', team_id)
      .eq('challenge_id', challenge_id)
      .maybeSingle();

    if (challengeError) {
      return new Response(
        JSON.stringify({ error: 'Error checking existing challenges.' }),
        { status: 500 }
      );
    }

    if (existingChallenge) {
      return new Response(
        JSON.stringify({ error: 'This challenge is already assigned to the team.' }),
        { status: 400 }
      );
    }

    // Check if user is already participating in another active team_challenge
    const { data: activeChallenges, error: activeError } = await supabase
      .from('user_contributions')
      .select('user_contribution_id')
      .eq('user_id', user_id)
      .eq('active', true);

    if (activeError) {
      return new Response(
        JSON.stringify({ error: 'Error checking user contributions.' }),
        { status: 500 }
      );
    }

    if (activeChallenges && activeChallenges.length > 0) {
      return new Response(
        JSON.stringify({ error: 'User is already part of an active team challenge.' }),
        { status: 400 }
      );
    }

    // Create a new team_challenge
    const { data: newTeamChallenge, error: createError } = await supabase
      .from('team_challenges')
      .insert({
        team_id,
        challenge_id,
        multiplier: 1,
        iscompleted: false,
      })
      .select('team_challenge_id')
      .single();

    if (createError || !newTeamChallenge) {
      return new Response(
        JSON.stringify({ error: 'Failed to create team challenge.' }),
        { status: 500 }
      );
    }

    return new Response(
      JSON.stringify({
        message: 'Team challenge successfully created.',
        team_challenge_id: newTeamChallenge.team_challenge_id,
      }),
      { status: 200 }
    );
  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal Server Error' }),
      { status: 500 }
    );
  }
});