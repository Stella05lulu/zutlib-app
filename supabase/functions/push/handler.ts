// ZutLib push: called by a Supabase Database Webhook each time a row is
// inserted into public.notifications. Sends that notification to every
// phone the person has registered, then marks it pushed.
//
// The webhook sends a shared secret in the x-zutlib-push-secret header;
// anything without it is refused. No user can call this to message others.

import { accessToken, Fetch, PushNote, sendAll, ServiceAccount } from './fcm.ts'

export type Deps = {
  secret: string
  serviceAccount: ServiceAccount | null
  fetch: Fetch
  now: () => number
  tokensFor: (userId: string) => Promise<string[]>
  deleteTokens: (tokens: string[]) => Promise<void>
  markPushed: (notificationId: string) => Promise<void>
  log: (event: string, fields?: Record<string, string | number | boolean>) => void
}

export type Outcome = { status: number; body: Record<string, unknown> }

function sameSecret(a: string, b: string): boolean {
  if (a.length === 0 || a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

export async function handle(headerSecret: string | null, body: unknown, d: Deps): Promise<Outcome> {
  if (!sameSecret(headerSecret ?? '', d.secret)) {
    d.log('refused')
    return { status: 401, body: { error: 'not_allowed' } }
  }
  const b = body as { type?: string; table?: string; record?: Record<string, unknown> } | null
  if (b?.type !== 'INSERT' || b?.table !== 'notifications' || !b.record) {
    return { status: 200, body: { ok: true, skipped: 'not a new notification' } }
  }
  const r = b.record
  const userId = typeof r.user_id === 'string' ? r.user_id : ''
  const note: PushNote = {
    id: typeof r.id === 'string' ? r.id : '',
    subject: typeof r.subject === 'string' ? r.subject : '',
    body: typeof r.body === 'string' ? r.body : '',
    link: typeof r.link === 'string' ? r.link : null,
  }
  if (!userId || !note.id || !note.subject) return { status: 400, body: { error: 'bad_record' } }
  if (!d.serviceAccount) {
    d.log('not_configured')
    return { status: 200, body: { ok: true, skipped: 'push is not set up' } }
  }

  const tokens = await d.tokensFor(userId)
  if (tokens.length === 0) return { status: 200, body: { ok: true, sent: 0 } }

  const token = await accessToken(d.serviceAccount, d.fetch, Math.floor(d.now() / 1000))
  const { sent, dead } = await sendAll(d.serviceAccount, token, tokens, note, d.fetch)
  if (dead.length > 0) await d.deleteTokens(dead)
  if (sent > 0) await d.markPushed(note.id)
  d.log('pushed', { sent, removed: dead.length })
  return { status: 200, body: { ok: true, sent, removed: dead.length } }
}
