import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'

// Load environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

// Create Supabase client using the service role key for insert operations
const supabase = createClient(supabaseUrl, supabaseKey)

serve(async (req: Request) => {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 })
  }

  // Parse the incoming JSON
  let body: any
  try {
    body = await req.json()
  } catch (e) {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), { status: 400 })
  }

  // Extract fields (validate as needed)
  const { start_time, duration, earning_points, difficulty, length } = body

  // Check required fields
  if (!start_time || !duration || !earning_points || !difficulty || !length) {
    return new Response(JSON.stringify({ error: 'Missing required fields' }), {
      status: 400,
    })
  }

  // Insert into the challenges table
  const { data, error } = await supabase
    .from('challenges')
    .insert({
      start_time,      // e.g. "2024-12-12T10:00:00Z" (ISO timestamp)
      duration,        // e.g. 60
      earning_points,  // e.g. 100
      difficulty,      // e.g. "easy", "medium", "hard"
      length         // e.g. 5
    })
    .select('*') // Returns the newly inserted rows

  // Handle potential error
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
    })
  }

  // Return the newly inserted record(s)
  return new Response(JSON.stringify({ data }), { status: 201 })
})