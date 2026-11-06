// ZutLib study-generate: AI summaries, flashcards and quizzes from a note.
//
// The app calls this with { "type": "kit" | "summary" | "flashcards" | "quiz",
// "note_id": "<uuid>" } and the student's sign-in token. The note can be
// typed text, a PDF the student uploaded, a PDF from the library or a
// YouTube video. "kit" makes a whole study kit in one request. The steps are in
// pipeline.ts; this file only connects them to the real services.
//
// Secrets: GEMINI_API_KEY is an Edge Function secret, set once with
//   supabase secrets set GEMINI_API_KEY=...
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are
// provided by Supabase automatically. None of them ever reaches the app.

import { MESSAGES, run } from './pipeline.ts'
import { restDeps } from './supabase_rest.ts'
import { callGemini } from './gemini.ts'

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

// One line per request, with no note text, no model output and no keys.
function log(event: string, fields: Record<string, string | number | boolean> = {}) {
  console.log(JSON.stringify({ fn: 'study-generate', event, ...fields }))
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') {
    return reply(405, { error: 'method_not_allowed', message: 'Use POST.' })
  }

  const apiKey = Deno.env.get('GEMINI_API_KEY') ?? ''
  const db = restDeps({
    url: Deno.env.get('SUPABASE_URL') ?? '',
    anonKey: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  })

  let body: unknown = null
  try {
    body = await req.json()
  } catch {
    body = null
  }

  try {
    const outcome = await run(req.headers.get('Authorization'), body, {
      ...db,
      generate: (kind, title, text, pdfs, youtubeUrls) => {
        if (!apiKey) {
          log('config_error', { reason: 'GEMINI_API_KEY not set' })
          return Promise.reject(new Error('missing key'))
        }
        return callGemini(apiKey, kind, title, text, pdfs, fetch, youtubeUrls)
      },
      log,
    })
    return reply(outcome.status, outcome.body)
  } catch (e) {
    log('server_error', { name: (e as Error).name })
    return reply(500, { error: 'server_error', message: MESSAGES.server_error })
  }
})
