import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

serve(async (req: Request) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
    }

    const body = await req.json();
    console.log('Received request body:', JSON.stringify(body, null, 2));

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

    // Step 1: Get active team
    console.log('Getting team membership for user:', user_id);
    const { data: teamMembership, error: teamError } = await supabase
      .from('team_memberships')
      .select('team_id')
      .eq('user_id', user_id)
      .is('date_left', null)
      .single();

    if (teamError) {
      console.error('Team membership error:', teamError);
      return new Response(
        JSON.stringify({ error: 'Error finding team membership', details: teamError.message }),
        { status: 400 }
      );
    }

    const team_id = teamMembership.team_id;
    console.log('Found team_id:', team_id);

    // Step 2: Get active challenge
    console.log('Getting active challenge for team:', team_id);
    const { data: activeChallenge, error: challengeError } = await supabase
      .from('team_challenges')
      .select(`
        team_challenge_id,
        challenge_id,
        challenges (length, start_time)
      `)
      .eq('team_id', team_id)
      .eq('iscompleted', false)
      .order('team_challenge_id', { ascending: false })
      .limit(1)
      .single();

    if (challengeError) {
      console.error('Active challenge error:', challengeError);
      return new Response(
        JSON.stringify({ error: 'Error fetching active challenge', details: challengeError.message }),
        { status: 500 }
      );
    }

    console.log('Found active challenge:', JSON.stringify(activeChallenge, null, 2));

    const totalDistance = totalContributions.reduce((sum, contribution) =>
      sum + (contribution.distance_covered || 0), 0);

    const challengeLength = activeChallenge.challenges.length * 1000;
    const isCompleted = totalDistance >= challengeLength;

    console.log(`Challenge progress: ${totalDistance}/${challengeLength} meters`);
    console.log('Is challenge completed?', isCompleted);

    if (isCompleted) {
      console.log('Challenge completed! Updating status...');

      // Mark as completed
      const { error: updateError } = await supabase
        .from('team_challenges')
        .update({ iscompleted: true })
        .eq('team_challenge_id', activeChallenge.team_challenge_id);

      if (updateError) {
        console.error('Error marking challenge as completed:', updateError);
      }

      // Update team streak
      console.log('Calling update_team_streak for team:', team_id);
      try {
        const streakUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/update_team_streak`;
        console.log('Calling streak URL:', streakUrl);

        const streakResponse = await fetch(
          streakUrl,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
            },
            body: JSON.stringify({ team_id }),
          }
        );

        const streakResult = await streakResponse.text();
        console.log('Streak update response:', streakResult);

        if (!streakResponse.ok) {
          console.error('Failed to update team streak:', streakResult);
        }
      } catch (err) {
        console.error('Error calling update_team_streak:', err);
      }
    }

    // Return response
    return new Response(
      JSON.stringify({
        data: {
          ...contributionData,
          team_challenge_id: activeChallenge.team_challenge_id,
          challenge_completed: isCompleted,
          total_distance_km: totalDistance / 1000,
          required_distance_km: challengeLength / 1000,
          challenge_start_time: activeChallenge.challenges.start_time
        },
      }),
      { status: 201 }
    );

  } catch (err) {
    console.error('Unexpected error:', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: err.message }),
      { status: 500 }
    );
  }
});