import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  let body: any
  try {
    body = await req.json()
  } catch (error) {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  // Extract and validate parameters
  const {
    team_challenge_id,
    user_id,
    start_time,
    start_latitude,
    start_longitude,
    distance_covered
  } = body

  // Enhanced validation
  const validationErrors = []
  if (typeof team_challenge_id !== 'number') validationErrors.push('team_challenge_id must be a number')
  if (typeof user_id !== 'number') validationErrors.push('user_id must be a number')
  if (typeof start_time !== 'string') validationErrors.push('start_time must be a string (ISO 8601)')
  if (typeof start_latitude !== 'number') validationErrors.push('start_latitude must be a number')
  if (typeof start_longitude !== 'number') validationErrors.push('start_longitude must be a number')
  if (typeof distance_covered !== 'number') validationErrors.push('distance_covered must be a number')

  if (validationErrors.length > 0) {
    return new Response(JSON.stringify({
      error: 'Invalid parameters',
      details: validationErrors
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  try {
    // Create end_time timestamp
    const end_time = new Date().toISOString()

    // Insert with proper numeric conversion
    const { data, error } = await supabase
      .from('user_contributions')
      .insert({
        team_challenge_id,
        user_id,
        start_time,
        end_time,  // Use actual end time
        start_latitude,
        end_latitude: start_latitude,  // Consider adding actual end location
        start_longitude,
        end_longitude: start_longitude,
        active: false,
        distance_covered: Number(distance_covered)  // Ensure numeric type
      })
      .select()
      .single()

    if (error) {
      console.error('Supabase error:', error)
      return new Response(JSON.stringify({
        error: 'Database operation failed',
        details: error.message
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    return new Response(JSON.stringify({ data }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response(JSON.stringify({
      error: 'Internal server error',
      details: err instanceof Error ? err.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})