import { assert, assertEquals, assertRejects } from './assert.ts'

import { accessToken, fcmMessage, parseServiceAccount, sendAll, ServiceAccount, signedAssertion } from '../fcm.ts'
import { Deps, handle } from '../handler.ts'

// A throwaway RSA key, made fresh for the tests.
const pair = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true,
  ['sign', 'verify'],
)
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey))
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8)).replace(/(.{64})/g, '$1\n')}\n-----END PRIVATE KEY-----\n`
const sa: ServiceAccount = { client_email: 'push@zutlib-test.iam.gserviceaccount.com', private_key: pem, project_id: 'zutlib-test' }

function b64urlDecode(s: string): Uint8Array {
  const b = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)
  return Uint8Array.from(atob(b), (c) => c.charCodeAt(0))
}

type Call = { url: string; init?: RequestInit }
function fakeFetch(responses: (url: string) => Response) {
  const calls: Call[] = []
  const f = (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    return Promise.resolve(responses(url))
  }
  return { f, calls }
}

const json = (v: unknown, status = 200) => new Response(JSON.stringify(v), { status })

Deno.test('a service account is read from its JSON, and junk is refused', () => {
  assertEquals(parseServiceAccount(JSON.stringify(sa))?.project_id, 'zutlib-test')
  assertEquals(parseServiceAccount('{"client_email": 1}'), null)
  assertEquals(parseServiceAccount('not json'), null)
})

Deno.test('the Google assertion is a valid RS256 JWT for FCM', async () => {
  const jwt = await signedAssertion(sa, 1_700_000_000)
  const [h, c, s] = jwt.split('.')
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(c)))
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(h))).alg, 'RS256')
  assertEquals(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging')
  assertEquals(claims.exp - claims.iat, 3600)
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', pair.publicKey, b64urlDecode(s), new TextEncoder().encode(`${h}.${c}`))
  assert(ok)
})

Deno.test('the access token comes from Google; a refusal throws', async () => {
  const good = fakeFetch(() => json({ access_token: 'ya29.token' }))
  assertEquals(await accessToken(sa, good.f, 1_700_000_000), 'ya29.token')
  assert(String(good.calls[0].init?.body).includes('grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer'))
  const bad = fakeFetch(() => json({ error: 'invalid_grant' }, 400))
  await assertRejects(() => accessToken(sa, bad.f, 1_700_000_000), (e) => String(e).includes('google_auth_400'))
})

Deno.test('a message carries the title, body and link', () => {
  const m = fcmMessage('tok', { id: 'n1', subject: 'Due back today', body: 'Programming in C', link: '/borrowing' })
  assertEquals(m.message.notification.title, 'Due back today')
  assertEquals(m.message.data.link, '/borrowing')
  assertEquals(m.message.token, 'tok')
})

Deno.test('tokens Firebase no longer knows are reported for deletion', async () => {
  const { f } = fakeFetch((url) => (url.includes('messages:send') ? json({}) : json({})))
  let n = 0
  const mixed = (url: string, init?: RequestInit) => {
    n++
    return n === 2
      ? Promise.resolve(new Response('{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}', { status: 404 }))
      : f(url, init)
  }
  const out = await sendAll(sa, 'ya29', ['a', 'b', 'c'], { id: 'n', subject: 's', body: 'b' }, mixed)
  assertEquals(out, { sent: 2, dead: ['b'] })
})

function deps(over: Partial<Deps> = {}) {
  const log: string[] = []
  const state = { deleted: [] as string[], pushed: [] as string[] }
  const { f, calls } = fakeFetch((url) => (url.includes('oauth2') ? json({ access_token: 'ya29' }) : json({ name: 'ok' })))
  const d: Deps = {
    secret: 'webhook-secret-123',
    serviceAccount: sa,
    fetch: f,
    now: () => 1_700_000_000_000,
    tokensFor: () => Promise.resolve(['token-1', 'token-2']),
    deleteTokens: (t) => {
      state.deleted.push(...t)
      return Promise.resolve()
    },
    markPushed: (id) => {
      state.pushed.push(id)
      return Promise.resolve()
    },
    log: (e) => log.push(e),
    ...over,
  }
  return { d, state, calls, log }
}

const insert = {
  type: 'INSERT',
  table: 'notifications',
  record: { id: 'n-1', user_id: 'u-1', subject: 'New past paper for EEE 2011', body: 'EEE 2011 examination 2025', link: '/resource/r-1' },
}

Deno.test('a call without the webhook secret is refused', async () => {
  const { d } = deps()
  assertEquals((await handle(null, insert, d)).status, 401)
  assertEquals((await handle('wrong-secret-12345', insert, d)).status, 401)
})

Deno.test('an empty configured secret refuses everything', async () => {
  const { d } = deps({ secret: '' })
  assertEquals((await handle('', insert, d)).status, 401)
})

Deno.test('a new notification is pushed to every phone and marked pushed', async () => {
  const { d, state, calls } = deps()
  const out = await handle('webhook-secret-123', insert, d)
  assertEquals(out.status, 200)
  assertEquals(out.body.sent, 2)
  assertEquals(state.pushed, ['n-1'])
  assertEquals(calls.filter((c) => c.url.includes('messages:send')).length, 2)
})

Deno.test('other webhook events are ignored', async () => {
  const { d, calls } = deps()
  const out = await handle('webhook-secret-123', { ...insert, type: 'UPDATE' }, d)
  assertEquals(out.status, 200)
  assertEquals(calls.length, 0)
})

Deno.test('without a Firebase service account nothing is sent', async () => {
  const { d, calls } = deps({ serviceAccount: null })
  const out = await handle('webhook-secret-123', insert, d)
  assertEquals(out.body.skipped, 'push is not set up')
  assertEquals(calls.length, 0)
})

Deno.test('someone with no registered phone gets nothing, and Google is not called', async () => {
  const { d, calls, state } = deps({ tokensFor: () => Promise.resolve([]) })
  const out = await handle('webhook-secret-123', insert, d)
  assertEquals(out.body.sent, 0)
  assertEquals(calls.length, 0)
  assertEquals(state.pushed, [])
})

Deno.test('a record missing its user is rejected', async () => {
  const { d } = deps()
  const out = await handle('webhook-secret-123', { ...insert, record: { id: 'x', subject: 's' } }, d)
  assertEquals(out.status, 400)
})
