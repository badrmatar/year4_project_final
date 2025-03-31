import { serve } from "https://deno.land/std@0.175.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req) => {
  const todayStr = new Date().toISOString().split("T")[0];
  const todayDate = new Date(todayStr);

  // get all teams
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
      if (!team.last_completion_date) continue;

      const lastDate = new Date(team.last_completion_date);
      //check the diff in days
      const diffDays = Math.floor(
        (todayDate.getTime() - lastDate.getTime()) / (1000 * 60 * 60 * 24)
      );
    //if more than 1 day reset
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
