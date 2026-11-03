// ZutLib push: delivers each new notification to the person's phones
// through Firebase Cloud Messaging. See handler.ts for the steps.
//
// Secrets (Supabase > Edge Functions > Secrets, never in the app):
//   FIREBASE_SERVICE_ACCOUNT  the Firebase service account JSON
//   PUSH_WEBHOOK_SECRET       any long random text; the same text goes in
//                             the database webhook's x-zutlib-push-secret header
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import { parseServiceAccount } from './fcm.ts'
import { handle } from './handler.ts'

const url = Deno.env.get('SUPABASE_URL') ?? ''
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const rest = (path: string, init: RequestInit = {}) =>
  fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  })

function log(event: string, fields: Record<string, string | number | boolean> = {}) {
  console.log(JSON.stringify({ fn: 'push', event, ...fields }))
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Use POST', { status: 405 })
  let body: unknown = null
  try {
    body = await req.json()
  } catch {
    body = null
  }
  try {
    const out = await handle(req.headers.get('x-zutlib-push-secret'), body, {
      secret: Deno.env.get('PUSH_WEBHOOK_SECRET') ?? '',
      serviceAccount: parseServiceAccount(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? ''),
      fetch: (input, init) => fetch(input, init),
      now: () => Date.now(),
      tokensFor: async (userId) => {
        const res = await rest(`device_tokens?select=token&user_id=eq.${encodeURIComponent(userId)}`)
        if (!res.ok) return []
        return ((await res.json()) as { token: string }[]).map((r) => r.token)
      },
      deleteTokens: async (tokens) => {
        const list = tokens.map((t) => `"${t.replace(/"/g, '')}"`).join(',')
        await rest(`device_tokens?token=in.(${encodeURIComponent(list)})`, { method: 'DELETE' })
      },
      markPushed: async (id) => {
        await rest(`notifications?id=eq.${encodeURIComponent(id)}`, {
          method: 'PATCH',
          body: JSON.stringify({ pushed_at: new Date().toISOString() }),
        })
      },
      log,
    })
    return new Response(JSON.stringify(out.body), { status: out.status, headers: { 'Content-Type': 'application/json' } })
  } catch (e) {
    log('server_error', { name: (e as Error).name, message: (e as Error).message.slice(0, 80) })
    return new Response(JSON.stringify({ error: 'server_error' }), { status: 500 })
  }
})
