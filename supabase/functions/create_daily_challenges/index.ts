import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serve } from 'https://deno.land/std@0.175.0/http/server.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const supabase = createClient(supabaseUrl, supabaseKey)

function getRandomInt(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}
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
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
    })
  }

  const start_time = new Date().toISOString()
  const duration = 24 * 60 // 24 hours in minutes

  //     5 random challenges
  const generatedChallenges = generateChallenges()
  const rowsToInsert = generatedChallenges.map((ch) => ({
    start_time,
    duration,
    length: ch.length,
    difficulty: ch.difficulty,
    earning_points: ch.earning_points,
  }))

  const { data, error } = await supabase
    .from('challenges')
    .insert(rowsToInsert)
    .select('*')
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
    })
  }

  return new Response(JSON.stringify({ data }), { status: 201 })
})