import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'

// Load environment variables
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

// Create a Supabase client using the service role key for insert operations
const supabase = createClient(supabaseUrl, supabaseKey)

/**
 * Generate a random integer in [min, max].
 */
function getRandomInt(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

/**
 * Calculate points using:
 *   earning_points = base + (length * 4)
 * Where:
 *   easy   => base = 10
 *   medium => base = 20
 *   hard   => base = 30
 */
function calculatePoints(length: number, difficulty: string): number {
  let base = 0
  switch (difficulty) {
    case 'easy':
      base = 10
      break
    case 'medium':
      base = 20
      break
    case 'hard':
      base = 30
      break
  }
  return base + length * 4
}

/**
 * Generate 5 challenges:
 *   2 easy   (length: 1–3)
 *   2 medium (length: 4–7)
 *   1 hard   (length: 8–10)
 */
function generateChallenges() {
  const challenges: Array<{
    length: number
    difficulty: string
    earning_points: number
  }> = []

  // 2 easy
  for (let i = 0; i < 2; i++) {
    const length = getRandomInt(1, 3)
    const difficulty = 'easy'
    challenges.push({
      length,
      difficulty,
      earning_points: calculatePoints(length, difficulty),
    })
  }

  // 2 medium
  for (let i = 0; i < 2; i++) {
    const length = getRandomInt(4, 7)
    const difficulty = 'medium'
    challenges.push({
      length,
      difficulty,
      earning_points: calculatePoints(length, difficulty),
    })
  }

  // 1 hard
  for (let i = 0; i < 1; i++) {
    const length = getRandomInt(8, 10)
    const difficulty = 'hard'
    challenges.push({
      length,
      difficulty,
      earning_points: calculatePoints(length, difficulty),
    })
  }

  return challenges
}

serve(async (req: Request) => {
  // Only allow POST
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
    })
  }

  // Hardcode start_time and duration
  const start_time = new Date().toISOString()
  const duration = 24 * 60 // 24 hours in minutes

  // Generate 5 random challenges
  const generatedChallenges = generateChallenges()

  // Prepare rows to insert into "challenges"
  const rowsToInsert = generatedChallenges.map((ch) => ({
    start_time,
    duration,
    length: ch.length,
    difficulty: ch.difficulty,
    earning_points: ch.earning_points,
  }))

  // Insert into the "challenges" table
  const { data, error } = await supabase
    .from('challenges')
    .insert(rowsToInsert)
    .select('*') // Return newly inserted rows

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
    })
  }

  // Return the newly inserted records
  return new Response(JSON.stringify({ data }), { status: 201 })
})