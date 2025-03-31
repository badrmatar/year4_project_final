export async function validatePostRequest(
  req: Request,
  requiredFields: string[] = []
): Promise<any | Response> {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const bodyText = await req.text();
  if (bodyText.trim() === '') {
    return new Response(JSON.stringify({ error: 'Request body cannot be empty.' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  let body;
  try {
    body = JSON.parse(bodyText);
  } catch (e) {
    return new Response(JSON.stringify({ error: 'Invalid JSON format.' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  for (const field of requiredFields) {
    if (!(field in body)) {
      return new Response(JSON.stringify({ error: `Missing required field: ${field}` }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  return body;
}
