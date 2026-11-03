// Firebase Cloud Messaging (HTTP v1) for ZutLib's push notifications.
//
// Supabase decides what to send and when; Firebase only delivers it to the
// phone. This file signs in to Google with the Firebase service account
// (an RS256-signed JWT exchanged for a short-lived access token) and sends
// one message per device token. Pure functions with the network passed in,
// so tests/push_test.ts runs them with a fake fetch.

export type ServiceAccount = { client_email: string; private_key: string; project_id: string }

export type Fetch = (input: string, init?: RequestInit) => Promise<Response>

export type PushNote = { id: string; subject: string; body: string; link?: string | null }

export function parseServiceAccount(json: string): ServiceAccount | null {
  try {
    const v = JSON.parse(json)
    if (typeof v?.client_email === 'string' && typeof v?.private_key === 'string' && typeof v?.project_id === 'string') {
      return { client_email: v.client_email, private_key: v.private_key, project_id: v.project_id }
    }
  } catch {
    // fall through
  }
  return null
}

function b64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes
  let s = ''
  for (const b of raw) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '')
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0))
  return await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
}

/** The signed assertion Google exchanges for an access token. */
export async function signedAssertion(sa: ServiceAccount, nowSeconds: number): Promise<string> {
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }))
  const key = await importKey(sa.private_key)
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`)))
  return `${header}.${claims}.${b64url(sig)}`
}

export async function accessToken(sa: ServiceAccount, fetchFn: Fetch, nowSeconds: number): Promise<string> {
  const assertion = await signedAssertion(sa, nowSeconds)
  const res = await fetchFn('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
  })
  if (!res.ok) throw new Error(`google_auth_${res.status}`)
  const data = await res.json()
  if (typeof data?.access_token !== 'string') throw new Error('google_auth_no_token')
  return data.access_token
}

/** One FCM v1 message. The link travels as data so tapping opens the screen. */
export function fcmMessage(token: string, note: PushNote) {
  return {
    message: {
      token,
      notification: { title: note.subject.slice(0, 200), body: note.body.slice(0, 1000) },
      data: { link: note.link ?? '', notification_id: note.id },
      android: { priority: 'high', notification: { channel_id: 'zutlib_push' } },
    },
  }
}

/** Sends [note] to every token. Returns how many were delivered and which
 *  tokens Firebase says no longer exist (to delete). */
export async function sendAll(
  sa: ServiceAccount, token: string, tokens: string[], note: PushNote, fetchFn: Fetch,
): Promise<{ sent: number; dead: string[] }> {
  let sent = 0
  const dead: string[] = []
  for (const t of tokens) {
    const res = await fetchFn(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(fcmMessage(t, note)),
    })
    if (res.ok) {
      sent++
    } else if (res.status === 404 || res.status === 400) {
      // UNREGISTERED or INVALID_ARGUMENT: the app was removed or the token is stale.
      const text = await res.text()
      if (res.status === 404 || text.includes('UNREGISTERED') || text.includes('registration token')) dead.push(t)
    } else {
      await res.body?.cancel()
    }
  }
  return { sent, dead }
}
