// ZutLib study-generate: the database and storage side, over Supabase's
// own REST API.
//
//   - GET /auth/v1/user with the caller's token. Supabase Auth answers only
//     if the token is genuine and unexpired, and tells us whose it is.
//   - POST /rest/v1/rpc/<function> with the service role key, for the
//     study_ai_* functions in 0010 and 0013. Those functions can only be
//     called with the service role, and each one takes the user id verified
//     above and checks the note belongs to that user.
//   - GET /storage/v1/object/<bucket>/<path> with the service role key, to
//     read the PDF that study_ai_prepare said belongs to this note.
//
// Plain fetch is used rather than the supabase-js library: these are the
// only calls needed, and it keeps the function free of downloads.

import type { CacheLookup, Deps, PreparedNote, SavedItem } from './pipeline.ts'
import { FileError, StoreError } from './pipeline.ts'
import type { GeneratedResult, Kind } from './validate.ts'
import { GEMINI_MODEL } from './config.ts'

export interface RestConfig {
  url: string
  anonKey: string
  serviceKey: string
  fetchFn?: typeof fetch
}

export function restDeps(cfg: RestConfig): Pick<
  Deps, 'verifyUser' | 'prepare' | 'downloadFile' | 'findCache' | 'materialise' | 'consume' | 'store'
> {
  const base = cfg.url.replace(/\/+$/, '')
  const f = cfg.fetchFn ?? fetch
  const service = { apikey: cfg.serviceKey, Authorization: `Bearer ${cfg.serviceKey}` }

  async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
    const res = await f(`${base}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { ...service, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    })
    const text = await res.text()
    const json = text ? JSON.parse(text) : null
    if (!res.ok) {
      // PostgREST reports a database error as { code, message }.
      const code = (json as { code?: string } | null)?.code ?? String(res.status)
      throw Object.assign(new Error(`${name} failed (${code})`), { pgCode: code })
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

    async prepare(userId, noteId, kind) {
      return await rpc('study_ai_prepare', { p_user: userId, p_note: noteId, p_kind: kind }) as PreparedNote
    },

    async downloadFile(bucket, path, maxBytes) {
      const encoded = path.split('/').map(encodeURIComponent).join('/')
      const res = await f(`${base}/storage/v1/object/${encodeURIComponent(bucket)}/${encoded}`, {
        headers: service,
      })
      if (!res.ok) {
        await res.body?.cancel()
        throw new FileError('file_missing', `storage HTTP ${res.status}`)
      }
      const declared = Number(res.headers.get('content-length') ?? '0')
      if (declared > maxBytes) {
        await res.body?.cancel()
        throw new FileError('file_too_large', `${declared} bytes`)
      }
      const bytes = new Uint8Array(await res.arrayBuffer())
      if (bytes.byteLength > maxBytes) throw new FileError('file_too_large', `${bytes.byteLength} bytes`)
      return bytes
    },

    async findCache(userId, noteId, kind, fileSha) {
      return await rpc('study_ai_cache_find', {
        p_user: userId, p_note: noteId, p_kind: kind, p_file_sha: fileSha,
      }) as CacheLookup
    },

    async materialise(userId, cacheId) {
      return await rpc('study_ai_materialise', { p_user: userId, p_cache: cacheId }) as SavedItem
    },

    async consume(userId) {
      return Number(await rpc('study_ai_consume', { p_user: userId }))
    },

    async store(userId: string, noteId: string, kind: Kind, hash: string,
                result: GeneratedResult, fileSha: string) {
      try {
        return await rpc('study_ai_store', {
          p_user: userId, p_note: noteId, p_kind: kind, p_hash: hash,
          p_model: GEMINI_MODEL, p_result: result, p_file_sha: fileSha,
        }) as SavedItem
      } catch (e) {
        const code = (e as { pgCode?: string }).pgCode
        // 40001: the note changed while Gemini worked. 23xxx: a table
        // constraint refused the content (the database's own shape check).
        if (code === '40001') throw new StoreError('note_changed', 'note changed')
        if (code?.startsWith('23')) throw new StoreError('invalid', `constraint ${code}`)
        throw new StoreError('failed', (e as Error).message)
      }
    },
  }
}
