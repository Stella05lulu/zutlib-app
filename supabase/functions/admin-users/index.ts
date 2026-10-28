// ZutLib admin-users: account management for administrators.
//
// The app calls this with the administrator's sign-in token and a body such
// as { "action": "create", "email": "...", "full_name": "...",
// "role": "librarian", "redirect_to": "<app address>" }. The steps and the
// list of actions are in handler.ts; this file connects them to Supabase.
//
// Secrets: none of its own. SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically and are
// never sent to the app.

import { run } from './handler.ts'
import { restDeps } from './rest.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

// One line per request: the event and outcome, never an email body or key.
function log(event: string, fields: Record<string, string | number | boolean> = {}) {
  console.log(JSON.stringify({ fn: 'admin-users', event, ...fields }))
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return reply(405, { error: 'method_not_allowed', message: 'Use POST.' })

  let body: unknown = null
  try {
    body = await req.json()
  } catch {
    body = null
  }

  const deps = restDeps({
    url: Deno.env.get('SUPABASE_URL') ?? '',
    anonKey: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  })

  try {
    const outcome = await run(req.headers.get('Authorization'), body, { ...deps, log })
    return reply(outcome.status, outcome.body)
  } catch (e) {
    log('server_error', { name: (e as Error).name })
    return reply(500, { error: 'server_error', message: 'Something went wrong on the server. Try again.' })
  }
})
