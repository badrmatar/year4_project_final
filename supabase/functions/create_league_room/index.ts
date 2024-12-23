import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Environment Variables
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

  const { league_room_name } = body

  if (typeof league_room_name !== 'string' || league_room_name.trim() === '') {
    return new Response(JSON.stringify({ error: 'league_room_name must be a non-empty string' }), { status: 400 })
  }

  // Insert new league room
  const { data, error } = await supabase
    .from('league_rooms')
    .insert({ league_room_name })
    .select('league_room_id, league_room_name')
    .single()

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }

  return new Response(JSON.stringify({
    league_room_id: data.league_room_id,
    league_room_name: data.league_room_name
  }), { status: 201 })
})

