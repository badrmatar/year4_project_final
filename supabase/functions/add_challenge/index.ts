// add_challenge/index.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { validatePostRequest } from './helpers.ts'  // Import your helper

// Load environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

// Create Supabase client using the service role key for insert operations
const supabase = createClient(supabaseUrl, supabaseKey)

serve(async (req: Request) => {
  // Use the helper to validate and parse the request.
  const result = await validatePostRequest(req, [
    'start_time',
    'duration',
    'earning_points',
    'difficulty',
    'length'
  ])
  
  // If the helper returns a Response, it's an error so return it immediately.
  if (result instanceof Response) return result
  
  // Otherwise, use the parsed JSON.
  const body = result
  const { start_time, duration, earning_points, difficulty, length } = body

  // Insert into the challenges table
  const { data, error } = await supabase
    .from('challenges')
    .insert({
      start_time,      // e.g. "2024-12-12T10:00:00Z"
      duration,        // e.g. 60
      earning_points,  // e.g. 100
      difficulty,      // e.g. "easy", "medium", "hard"
      length           // e.g. 5
    })
    .select('*') // Returns the newly inserted rows

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify({ data }), {
    status: 201,
    headers: { 'Content-Type': 'application/json' }
  })
})
