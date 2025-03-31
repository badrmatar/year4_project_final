import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      {
        status: 405,
        headers: { 'Content-Type': 'application/json' }
      }
    );
  }

  try {
    const body = await req.json();
    console.log('Received request body:', body);

    const {
      user_id,
      start_time,
      end_time,
      start_latitude,
      start_longitude,
      end_latitude,
      end_longitude,
      distance_covered,
      route,
      journey_type,
    } = body;

    const validationErrors = [];
    if (typeof user_id !== 'number') validationErrors.push('user_id must be a number');
    if (typeof start_time !== 'string') validationErrors.push('start_time must be a string');
    if (typeof distance_covered !== 'number') validationErrors.push('distance_covered must be a number');
    if (!Array.isArray(route)) validationErrors.push('route must be an array');

    if (validationErrors.length > 0) {
      return new Response(
        JSON.stringify({ error: 'Validation failed', details: validationErrors }),
        { status: 400 }
      );
    }

    const journeyType = (typeof journey_type === 'string' && (journey_type === 'duo' || journey_type === 'solo'))
      ? journey_type
      : 'solo';
    console.log('Computed journeyType:', journeyType);

    // Get user's active team
    const { data: teamMembership, error: teamError } = await supabase
      .from('team_memberships')
      .select('team_id')
      .eq('user_id', user_id)
      .is('date_left', null)
      .single();

    if (teamError) {
      console.error('Team error:', teamError);
      return new Response(
        JSON.stringify({ error: 'Failed to get team membership' }),
        { status: 400 }
      );
    }

    // Get active team challenge
    const { data: teamChallenge, error: challengeError } = await supabase
      .from('team_challenges')
      .select(`
        team_challenge_id,
        challenges (
          length
        )
      `)
      .eq('team_id', teamMembership.team_id)
      .eq('iscompleted', false)
      .order('team_challenge_id', { ascending: false })
      .limit(1)
      .single();

    if (challengeError || !teamChallenge) {
      console.error('Challenge error:', challengeError);
      return new Response(
        JSON.stringify({ error: 'No active challenge found' }),
        { status: 400 }
      );
    }

    // add contubtion
    const { data: newContribution, error: insertError } = await supabase
      .from('user_contributions')
      .insert({
        team_challenge_id: teamChallenge.team_challenge_id,
        user_id,
        start_time,
        end_time: end_time ?? new Date().toISOString(),
        start_latitude,
        start_longitude,
        end_latitude,
        end_longitude,
        distance_covered,
        route,
        journey_type: journeyType,
        active: false,
        contribution_details: `Distance covered: ${distance_covered}m`
      })
      .select()
      .single();

    if (insertError) {
      console.error('Insert error:', insertError);
      return new Response(
        JSON.stringify({ error: 'Failed to save contribution' }),
        { status: 400 }
      );
    }

    // all challenge contirbution
    const { data: allContributions, error: sumError } = await supabase
      .from('user_contributions')
      .select('distance_covered, journey_type')
      .eq('team_challenge_id', teamChallenge.team_challenge_id);

    if (sumError) {
      console.error('Sum error:', sumError);
      return new Response(
        JSON.stringify({ error: 'Failed to calculate total distance' }),
        { status: 400 }
      );
    }
    const totalMeters = allContributions.reduce((sum, c) => sum + (c.distance_covered || 0), 0); //total calc
    const totalKm = totalMeters / 1000;
    const requiredKm = teamChallenge.challenges.length;
    const isCompleted = totalKm >= requiredKm;
    console.log('Total km:', totalKm, ' Required km:', requiredKm, ' Challenge Completed:', isCompleted);

    const duoMeters = allContributions
      .filter((c) => c.journey_type === 'duo') //calculates the distance i duo mode
      .reduce((sum, c) => sum + (c.distance_covered || 0), 0);
    const duoDistanceKm = duoMeters / 1000;

    if (duoDistanceKm >= requiredKm / 2) {//if morec than half give them multi
      const { error: multiplierUpdateError } = await supabase
        .from('team_challenges')
        .update({ multiplier: 2 })
        .eq('team_challenge_id', teamChallenge.team_challenge_id);
      if (multiplierUpdateError) {
        console.error('Multiplier update error:', multiplierUpdateError);
      } else {
        console.log(
          `Multiplier updated to 2 for team_challenge_id ${teamChallenge.team_challenge_id} because duo distance ${duoDistanceKm} km reached half of required ${requiredKm} km`
        );
      }
    }
    if (isCompleted) {
      console.log('Challenge completed! Updating status and streak...');


      const { error: updateError } = await supabase
        .from('team_challenges')
        .update({ iscompleted: true })
        .eq('team_challenge_id', teamChallenge.team_challenge_id);

      if (updateError) {
        console.error('Error marking challenge as completed:', updateError);
      }

      // update streak and check for bonus
      const today = new Date().toISOString().split('T')[0];

      const { data: team, error: teamError } = await supabase
        .from('teams')
        .select('current_streak, last_completion_date, streak_bonus_points')
        .eq('team_id', teamMembership.team_id)
        .single();

      if (!teamError && team) {
        let newStreak = 1;
        let newBonusPoints = team.streak_bonus_points || 0;

        if (team.last_completion_date) {
          const lastCompletion = new Date(team.last_completion_date);
          const daysDifference = Math.floor(
            (new Date(today).getTime() - lastCompletion.getTime()) / (1000 * 60 * 60 * 24)
          );

          if (daysDifference === 0) {
            newStreak = team.current_streak;
          } else if (daysDifference === 1) {
            newStreak = team.current_streak + 1;

            // Award bonus every 3 days
            if (newStreak % 3 === 0) {
              newBonusPoints += 100;
              console.log('Awarding 100 bonus points for 3-day streak!');
            }
          }
        }

        const { error: streakError } = await supabase
          .from('teams')
          .update({
            current_streak: newStreak,
            last_completion_date: today,
            streak_bonus_points: newBonusPoints
          })
          .eq('team_id', teamMembership.team_id);

        if (streakError) {
          console.error('Error updating team:', streakError);
        } else {
          console.log('Successfully updated team:', {
            streak: newStreak,
            bonusPoints: newBonusPoints,
            team_id: teamMembership.team_id
          });
        }
      } else {
        console.error('Error fetching team data:', teamError);
      }
    }

    const response = {
      data: {
        ...newContribution,
        challenge_completed: isCompleted,
        total_distance_km: totalKm,
        required_distance_km: requiredKm,
        duo_distance: duoDistanceKm
      }
    };

    console.log('Sending response:', JSON.stringify(response, null, 2));

    return new Response(
      JSON.stringify(response),
      {
        status: 201,
        headers: { 'Content-Type': 'application/json' }
      }
    );

  } catch (err) {
    console.error('Unexpected error:', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: err.message }),
      { status: 500 }
    );
  }
});