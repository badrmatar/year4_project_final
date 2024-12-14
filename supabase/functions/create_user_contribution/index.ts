import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 })
  }

  let body: any
  try {
    body = await req.json()
  } catch (error) {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), { status: 400 })
  }

  const { team_challenge_id, user_id, start_time, start_latitude, start_longitude } = body

  // Validate input
  if (typeof team_challenge_id !== 'number' ||
      typeof user_id !== 'number' ||
      typeof start_time !== 'string' ||
      typeof start_latitude !== 'number' ||
      typeof start_longitude !== 'number') {
    return new Response(JSON.stringify({
      error: 'Invalid or missing parameters. Check that team_challenge_id, user_id, start_latitude, and start_longitude are numbers and start_time is a string (ISO 8601 timestamp).'
    }), { status: 400 })
  }

  // Insert the new user contribution
  const { data, error } = await supabase
    .from('user_contributions')
    .insert({
      team_challenge_id,
      user_id,
      start_time,
      end_time: start_time,
      start_latitude,
      end_latitude: start_latitude,
      start_longitude,
      end_longitude: start_longitude,
      active: true
    })
    .select()
    .single()

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }

  return new Response(JSON.stringify({ data }), { status: 201 })
})
