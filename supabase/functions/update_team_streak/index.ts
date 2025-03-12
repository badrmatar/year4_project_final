// supabase/functions/update_team_streak/index.ts
import { serve } from 'https://deno.land/std@0.175.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
    }

    const { team_id } = await req.json();
    console.log('Updating streak for team_id:', team_id);

    if (!team_id) {
      return new Response(JSON.stringify({ error: 'team_id is required' }), { status: 400 });
    }

    // Get the team's current streak info
    const { data: team, error: teamError } = await supabase
      .from('teams')
      .select('current_streak, last_completion_date, team_name')
      .eq('team_id', team_id)
      .single();

    if (teamError) {
      console.error('Error fetching team data:', teamError);
      return new Response(JSON.stringify({ error: teamError.message }), { status: 400 });
    }

    console.log('Current team state:', {
      team_name: team.team_name,
      current_streak: team.current_streak,
      last_completion: team.last_completion_date
    });

    const today = new Date();
    const todayDate = today.toISOString().split('T')[0];

    // If there's no last completion date, this is the first completion
    if (!team.last_completion_date) {
      console.log('First completion for team - initializing streak');
      const { data, error } = await supabase
        .from('teams')
        .update({
          current_streak: 1,
          last_completion_date: todayDate
        })
        .eq('team_id', team_id)
        .select();

      if (error) {
        console.error('Error updating first streak:', error);
        throw error;
      }
      console.log('Successfully initialized streak');
      return new Response(JSON.stringify({ data }), { status: 200 });
    }

    // Calculate days between last completion and today
    const lastCompletion = new Date(team.last_completion_date);
    const daysDifference = Math.floor(
      (today.getTime() - lastCompletion.getTime()) / (1000 * 60 * 60 * 24)
    );

    console.log('Days since last completion:', daysDifference);

    let newStreak = team.current_streak;

    // If completed today, no change
    if (daysDifference === 0) {
      console.log('Already completed challenge today - no streak change');
      return new Response(
        JSON.stringify({
          message: 'Already completed challenge today',
          current_streak: newStreak
        }),
        { status: 200 }
      );
    }
    // If completed yesterday, increment streak
    else if (daysDifference === 1) {
      newStreak += 1;
      console.log('Consecutive day completion - incrementing streak to:', newStreak);
    }
    // If more than one day has passed, reset streak to 1
    else {
      newStreak = 1;
      console.log('Streak reset to 1 due to gap in completions');
    }

    // Update the team's streak information
    const { data, error } = await supabase
      .from('teams')
      .update({
        current_streak: newStreak,
        last_completion_date: todayDate
      })
      .eq('team_id', team_id)
      .select();

    if (error) {
      console.error('Error updating streak:', error);
      throw error;
    }

    console.log('Successfully updated streak. New state:', data);

    return new Response(JSON.stringify({
      data,
      streak_change: {
        previous_streak: team.current_streak,
        new_streak: newStreak,
        days_difference: daysDifference
      }
    }), { status: 200 });
  } catch (error) {
    console.error('Unexpected error in update_team_streak:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500 }
    );
  }
});