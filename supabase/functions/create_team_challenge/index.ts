import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const supabase = createClient(supabaseUrl, supabaseKey)

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

  const { team_id, challenge_id } = body
  if (typeof team_id !== 'number' || typeof challenge_id !== 'number') {
    return new Response(JSON.stringify({ error: 'team_id and challenge_id must be numbers' }), { status: 400 })
  }

  const { data, error } = await supabase
    .from('team_challenges')
    .insert({
      team_id: team_id,
      challenge_id: challenge_id,
      multiplier: 1,
      iscompleted: false
    })
    .select()

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }

  return new Response(JSON.stringify({ data }), { status: 201 })
})