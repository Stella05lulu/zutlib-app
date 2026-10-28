// A small stand-in for the parts of a Supabase project the Edge Functions
// talk to, used only by the local end-to-end tests:
//
//   /auth/v1/user             checks a token's signature, like Supabase Auth
//   /auth/v1/invite           creates the user in the real local database
//                             (so the sign-up trigger runs) and records
//                             that an invite email "was sent"
//   /auth/v1/admin/users/:id  reads a user from the local database
//   /storage/v1/object/...    serves files the test has put in `files`
//   /rest/v1/*                forwarded to the real PostgREST
//
// Nothing here is deployed.

export const SECRET = Deno.env.get('JWT_SECRET') ?? ''
export const PGRST = Deno.env.get('PGRST_URL') ?? 'http://127.0.0.1:3010'
const PSQL = (Deno.env.get('PSQL') ?? 'psql').split(' ')

const b64url = (b: Uint8Array) =>
  btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

export async function jwt(claims: Record<string, unknown>, secret = SECRET): Promise<string> {
  const enc = new TextEncoder()
  const head = b64url(enc.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })))
  const body = b64url(enc.encode(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 600, ...claims })))
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(`${head}.${body}`)))
  return `${head}.${body}.${b64url(sig)}`
}

export async function verify(token: string): Promise<Record<string, unknown> | null> {
  const [h, p, s] = token.split('.')
  if (!h || !p || !s) return null
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey('raw', enc.encode(SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
  const sig = Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0))
  if (!await crypto.subtle.verify('HMAC', key, sig, enc.encode(`${h}.${p}`))) return null
  const claims = JSON.parse(atob(p.replace(/-/g, '+').replace(/_/g, '/')))
  return claims.exp > Date.now() / 1000 ? claims : null
}

export async function sql(query: string): Promise<string> {
  const out = await new Deno.Command(PSQL[0], {
    args: [...PSQL.slice(1), '-v', 'ON_ERROR_STOP=1', '-qtAc', query],
  }).output()
  if (!out.success) throw new Error(new TextDecoder().decode(out.stderr))
  return new TextDecoder().decode(out.stdout).trim()
}

const lit = (v: string) => `'${v.replace(/'/g, "''")}'`

export interface Gateway {
  url: string
  /** "bucket/path" -> bytes, served by the storage stand-in. */
  files: Map<string, Uint8Array>
  /** Every invite email that would have been sent. */
  invites: { email: string; redirectTo: string | null }[]
  recoveries: { email: string; redirectTo: string | null }[]
  /** Make the next invite fail with this status and message. */
  failNextInvite: { status: number; msg: string } | null
  close(): Promise<void>
}

export function startGateway(): Gateway {
  const gw: Gateway = {
    url: '',
    files: new Map(),
    invites: [],
    recoveries: [],
    failNextInvite: null,
    close: async () => {},
  }

  async function isService(req: Request) {
    const claims = await verify((req.headers.get('Authorization') ?? '').replace(/^Bearer /, ''))
    return claims?.role === 'service_role'
  }

  const server = Deno.serve({ port: 0, hostname: '127.0.0.1', onListen: () => {} }, async (req) => {
    const u = new URL(req.url)

    if (u.pathname === '/auth/v1/user') {
      const claims = await verify((req.headers.get('Authorization') ?? '').replace(/^Bearer /, ''))
      if (!claims || claims.role !== 'authenticated') {
        return new Response('{"msg":"invalid JWT"}', { status: 401 })
      }
      return Response.json({ id: claims.sub })
    }

    if (u.pathname === '/auth/v1/invite' && req.method === 'POST') {
      if (!await isService(req)) return new Response('{"msg":"not admin"}', { status: 401 })
      const { email, data } = await req.json() as { email: string; data: Record<string, string> }
      if (gw.failNextInvite) {
        const f = gw.failNextInvite
        gw.failNextInvite = null
        return Response.json({ code: f.status, msg: f.msg }, { status: f.status })
      }
      const existing = await sql(
        `select id || '|' || (email_confirmed_at is not null) from auth.users where lower(email) = lower(${lit(email)})`)
      let id: string
      if (existing) {
        const [eid, confirmed] = existing.split('|')
        if (confirmed === 'true') {
          return Response.json({ code: 422, error_code: 'email_exists',
            msg: 'A user with this email address has already been registered' }, { status: 422 })
        }
        id = eid
      } else {
        id = crypto.randomUUID()
        await sql(`insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
                   values (${lit(id)}, ${lit(email)}, null, ${lit(JSON.stringify(data ?? {}))}::jsonb)`)
      }
      gw.invites.push({ email, redirectTo: u.searchParams.get('redirect_to') })
      return Response.json({ id, email, email_confirmed_at: null })
    }

    if (u.pathname === '/auth/v1/recover' && req.method === 'POST') {
      const { email } = await req.json() as { email: string }
      gw.recoveries.push({ email, redirectTo: u.searchParams.get('redirect_to') })
      return Response.json({})
    }

    const userMatch = /^\/auth\/v1\/admin\/users\/([0-9a-f-]{36})$/.exec(u.pathname)
    if (userMatch && req.method === 'GET') {
      if (!await isService(req)) return new Response('{"msg":"not admin"}', { status: 401 })
      const row = await sql(`select coalesce(email, '') || '|' || coalesce(email_confirmed_at::text, '')
                               from auth.users where id = ${lit(userMatch[1])}`)
      if (!row) return Response.json({ msg: 'User not found' }, { status: 404 })
      const [email, confirmedAt] = row.split('|')
      return Response.json({ id: userMatch[1], email, email_confirmed_at: confirmedAt || null })
    }

    // Uploads and deletes (used by scripts/sample_data.py). They also keep
    // storage.objects in step, so row level security on files is real.
    if (u.pathname.startsWith('/storage/v1/object/') && req.method === 'POST') {
      if (!await isService(req)) return new Response('{"error":"unauthorized"}', { status: 400 })
      const key = decodeURIComponent(u.pathname.slice('/storage/v1/object/'.length))
      const [bucket, ...rest] = key.split('/')
      gw.files.set(key, new Uint8Array(await req.arrayBuffer()))
      await sql(`select set_config('storage.allow_delete_query', 'true', false);
                 delete from storage.objects where bucket_id = ${lit(bucket)} and name = ${lit(rest.join('/'))};
                 insert into storage.objects (bucket_id, name) values (${lit(bucket)}, ${lit(rest.join('/'))})`)
      return Response.json({ Key: key })
    }
    const bucketDelete = /^\/storage\/v1\/object\/([^/]+)$/.exec(u.pathname)
    if (bucketDelete && req.method === 'DELETE') {
      if (!await isService(req)) return new Response('{"error":"unauthorized"}', { status: 400 })
      const { prefixes } = await req.json() as { prefixes: string[] }
      for (const p of prefixes) {
        gw.files.delete(`${bucketDelete[1]}/${p}`)
        await sql(`select set_config('storage.allow_delete_query', 'true', false);
                   delete from storage.objects where bucket_id = ${lit(bucketDelete[1])} and name = ${lit(p)}`)
      }
      return Response.json(prefixes.map((name) => ({ name })))
    }

    if (u.pathname.startsWith('/storage/v1/object/') && req.method === 'GET') {
      if (!await isService(req)) return new Response('{"error":"unauthorized"}', { status: 400 })
      const key = decodeURIComponent(u.pathname.slice('/storage/v1/object/'.length))
      const bytes = gw.files.get(key)
      if (!bytes) return new Response('{"error":"not_found"}', { status: 400 })
      return new Response(bytes, { headers: { 'Content-Type': 'application/pdf', 'Content-Length': String(bytes.byteLength) } })
    }

    if (u.pathname.startsWith('/rest/v1/')) {
      return await fetch(PGRST + u.pathname.slice('/rest/v1'.length) + u.search, {
        method: req.method,
        headers: {
          'Content-Type': 'application/json',
          Authorization: req.headers.get('Authorization') ?? '',
          Prefer: req.headers.get('Prefer') ?? '',
          Accept: req.headers.get('Accept') ?? 'application/json',
        },
        body: req.method === 'GET' ? undefined : await req.text(),
      })
    }
    return new Response('not found', { status: 404 })
  })
  gw.url = `http://127.0.0.1:${server.addr.port}`
  gw.close = () => server.shutdown()
  return gw
}
