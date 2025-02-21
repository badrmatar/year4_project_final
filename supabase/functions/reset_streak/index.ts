// reset_streak/index.ts
import { serve } from "https://deno.land/std@0.175.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Initialize the Supabase client with your service role key.
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req) => {
  // Get today's date as a string (YYYY-MM-DD) and convert to a Date object.
  const todayStr = new Date().toISOString().split("T")[0];
  const todayDate = new Date(todayStr);

  // Fetch all teams with their last_completion_date and current_streak.
  const { data: teams, error } = await supabase
    .from("teams")
    .select("team_id, last_completion_date, current_streak");

  if (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  let updateCount = 0;
  if (teams) {
    for (const team of teams) {
      // Skip teams that have no recorded completion date.
      if (!team.last_completion_date) continue;

      const lastDate = new Date(team.last_completion_date);
      // Calculate the difference in whole days.
      const diffDays = Math.floor(
        (todayDate.getTime() - lastDate.getTime()) / (1000 * 60 * 60 * 24)
      );

      // If the gap is more than 1 day (i.e. last completion is not yesterday),
      // then reset the streak to 0.
      if (diffDays > 1 && team.current_streak !== 0) {
        const { error: updateError } = await supabase
          .from("teams")
          .update({ current_streak: 0 })
          .eq("team_id", team.team_id);
        if (!updateError) {
          updateCount++;
        }
      }
    }
  }

  return new Response(
    JSON.stringify({ message: "Streaks updated", teamsUpdated: updateCount }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
