import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'
import { validatePostRequest } from './helpers.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const supabase = createClient(supabaseUrl, supabaseKey)

serve(async (req: Request) => {
  const result = await validatePostRequest(req, [
    'start_time',
    'duration',
    'earning_points',
    'difficulty',
    'length'
  ])
    if (result instanceof Response) return result

  const body = result
  const { start_time, duration, earning_points, difficulty, length } = body
  const { data, error } = await supabase
    .from('challenges')
    .insert({
      start_time,
      duration,
      earning_points,
      difficulty,
      length
    })
    .select('*')

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
