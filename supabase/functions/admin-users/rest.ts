// ZutLib admin-users: the Supabase side, over its REST API.
//
//   GET  /auth/v1/user                  who the caller is (their own token)
//   POST /auth/v1/invite                Supabase's invite email; makes the
//                                       user if they do not exist yet
//   GET  /auth/v1/admin/users/<id>      one user's email and whether they
//                                       have confirmed it
//   POST /auth/v1/recover               the password email, for an invite
//                                       opened but never finished
//   GET  /rest/v1/profiles              whether a password is still needed
//   POST /rest/v1/rpc/admin_*           the checked, audited database
//                                       functions from 0012
//
// The Auth admin endpoints and the admin_* functions need the service role
// key, which Supabase gives this function as SUPABASE_SERVICE_ROLE_KEY. It
// never leaves the server.

import { AuthApiError, type AuthUser, DbError, type Deps } from './handler.ts'

export interface RestConfig {
  url: string
  anonKey: string
  serviceKey: string
  fetchFn?: typeof fetch
}

function toAuthUser(u: Record<string, unknown>): AuthUser {
  return {
    id: String(u.id),
    email: String(u.email ?? ''),
    confirmed: Boolean(u.email_confirmed_at ?? u.confirmed_at),
  }
}

export function restDeps(cfg: RestConfig): Omit<Deps, 'log'> {
  const base = cfg.url.replace(/\/+$/, '')
  const f = cfg.fetchFn ?? fetch
  const service = { apikey: cfg.serviceKey, Authorization: `Bearer ${cfg.serviceKey}` }

  async function authCall(path: string, init: RequestInit): Promise<Record<string, unknown>> {
    const res = await f(`${base}/auth/v1${path}`, {
      ...init,
      headers: { ...service, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
    })
    const text = await res.text()
    let json: Record<string, unknown> = {}
    try {
      json = text ? JSON.parse(text) : {}
    } catch {
      json = { msg: text }
    }
    if (!res.ok) {
      const message = String(json.msg ?? json.message ?? json.error_description ?? json.error ?? `HTTP ${res.status}`)
      throw new AuthApiError(res.status, String(json.error_code ?? json.code ?? ''), message)
    }
    return json
  }

  async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
    const res = await f(`${base}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { ...service, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    })
    const text = await res.text()
    const json = text ? JSON.parse(text) : null
    if (!res.ok) {
      const j = (json ?? {}) as { code?: string; message?: string }
      throw new DbError(j.code ?? String(res.status), j.message ?? `${name} failed`)
    }
    return json
  }

  return {
    async verifyUser(token) {
      const res = await f(`${base}/auth/v1/user`, {
        headers: { apikey: cfg.anonKey, Authorization: `Bearer ${token}` },
      })
      if (!res.ok) {
        await res.body?.cancel()
        return null
      }
      const user = await res.json() as { id?: string }
      return typeof user.id === 'string' ? user.id : null
    },

    async isAdmin(userId) {
      return (await rpc('admin_is_admin', { p_user: userId })) === true
    },

    async isSuperAdmin(userId) {
      return (await rpc('admin_is_super', { p_user: userId })) === true
    },

    async canManage(actor, target) {
      return (await rpc('admin_can_manage', { p_actor: actor, p_target: target })) === true
    },

    async invite(email, data, redirectTo) {
      const q = redirectTo ? `?redirect_to=${encodeURIComponent(redirectTo)}` : ''
      const json = await authCall(`/invite${q}`, {
        method: 'POST',
        body: JSON.stringify({ email, data }),
      })
      return toAuthUser(json)
    },

    async getUser(userId) {
      try {
        return toAuthUser(await authCall(`/admin/users/${userId}`, { method: 'GET' }))
      } catch (e) {
        if (e instanceof AuthApiError && e.status === 404) return null
        throw e
      }
    },

    async needsPassword(userId) {
      const res = await f(`${base}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=must_set_password`, {
        headers: { ...service, Accept: 'application/json' },
      })
      if (!res.ok) {
        const text = await res.text()
        throw new DbError(String(res.status), text || 'profile lookup failed')
      }
      const rows = await res.json() as Array<{ must_set_password?: boolean }>
      return rows[0]?.must_set_password === true
    },

    async sendSetupLink(email, redirectTo) {
      const q = redirectTo ? `?redirect_to=${encodeURIComponent(redirectTo)}` : ''
      await authCall(`/recover${q}`, { method: 'POST', body: JSON.stringify({ email }) })
    },

    async afterInvite(actor, user, role, fullName, department, test) {
      return await rpc('admin_after_invite', {
        p_actor: actor, p_user: user, p_role: role,
        p_full_name: fullName, p_department: department, p_test: test,
      }) as Record<string, unknown>
    },

    async apply(actor, target, action, role, reason) {
      return await rpc('admin_apply', {
        p_actor: actor, p_target: target, p_action: action, p_role: role, p_reason: reason,
      }) as Record<string, unknown>
    },

    async record(actor, action, target, detail) {
      await rpc('admin_record', { p_actor: actor, p_action: action, p_target: target, p_detail: detail })
    },
  }
}
