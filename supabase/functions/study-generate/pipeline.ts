// ZutLib study-generate: the steps, in the order they run.
//
//   1. verify the caller's sign-in token        -> 401 if missing or invalid
//   2. check the student's daily limit          -> 429 if used up
//      (the same call loads the note, but only if it is the caller's own,
//       and says where its PDF is, if it has one)
//   3. check the input is not too long          -> 413
//      typed text over MAX_INPUT_CHARS, or a PDF over MAX_PDF_BYTES
//   4. look in the cache for this exact content -> answer from there, no AI
//      (the key includes a fingerprint of the PDF's bytes)
//   5. take one request from today's allowance, then call Gemini
//   6. validate Gemini's answer                 -> 502, nothing stored
//   7. save the result in the cache and as the student's item
//   8. return it
//
// Everything that reaches the network or the database is passed in as
// `deps`, so the tests can run every step with stand-ins and count, for
// example, how many times Gemini would have been called.
//
// Nothing here logs note text, PDF content or model output: only event
// names, the request type and outcome codes.

import { MAX_INPUT_CHARS, MAX_PDF_BYTES } from './config.ts'
import { InvalidOutput, KINDS, validateOutput, type GeneratedResult, type Kind } from './validate.ts'
import { ModelError } from './gemini.ts'

export interface PreparedNote {
  error?: string
  title?: string
  body?: string
  remaining?: number
  /** 'study-files' for a student's upload, 'resources' for a library PDF. */
  file_bucket?: string | null
  file_path?: string | null
  /** A kit's YouTube video, in the standard watch form. */
  youtube_url?: string | null
}

export interface CacheLookup {
  content_hash: string
  cache_id: string | null
}

export interface SavedItem {
  kind: Kind
  id: string
  reused: boolean
}

export class StoreError extends Error {
  constructor(public code: 'note_changed' | 'invalid' | 'failed', detail: string) {
    super(detail)
  }
}

export class FileError extends Error {
  constructor(public code: 'file_too_large' | 'file_missing' | 'not_pdf', detail: string) {
    super(detail)
  }
}

export interface Deps {
  /** Returns the account id for a valid token, or null. */
  verifyUser(token: string): Promise<string | null>
  prepare(userId: string, noteId: string, kind: Kind): Promise<PreparedNote>
  /** Fetches a stored PDF; throws FileError if it is missing or over maxBytes. */
  downloadFile(bucket: string, path: string, maxBytes: number): Promise<Uint8Array>
  findCache(userId: string, noteId: string, kind: Kind, fileSha: string): Promise<CacheLookup>
  materialise(userId: string, cacheId: string): Promise<SavedItem>
  /** Takes one request from today's allowance; returns how many are left,
   *  -1 if the student's limit is used up, -2 if the project's is. */
  consume(userId: string): Promise<number>
  /** Returns Gemini's raw answer text. */
  generate(kind: Kind, title: string, body: string, pdf: Uint8Array | null, youtubeUrl: string | null): Promise<string>
  store(
    userId: string, noteId: string, kind: Kind, hash: string,
    result: GeneratedResult, fileSha: string,
  ): Promise<SavedItem>
  log(event: string, fields?: Record<string, string | number | boolean>): void
}

export interface Outcome {
  status: number
  body: Record<string, unknown>
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const MB = Math.round(MAX_PDF_BYTES / (1024 * 1024))

// What the student reads when something goes wrong. Plain, specific, and
// always says what still works.
export const MESSAGES = {
  unauthenticated: 'Sign in again to use AI help.',
  bad_request: 'That request was not understood. Update the app and try again.',
  not_student: 'AI help is available to approved student accounts only.',
  not_found: 'That note could not be found. It may have been deleted.',
  no_source: 'This kit has no materials yet. Add a PDF, a YouTube video or some text first.',
  limit_reached: 'You have used all of today\'s AI requests. They renew at midnight. Everything else still works.',
  project_limit_reached: 'AI help has reached its limit for today across ZutLib. Try again tomorrow. Everything else still works.',
  input_too_long: `This note is too long for AI help. Keep the typed text under ${MAX_INPUT_CHARS.toLocaleString('en')} characters, or split it into two notes.`,
  file_too_large: `This PDF is larger than ${MB} MB, which is too big for AI help. Try a smaller file, for example one chapter.`,
  file_missing: 'The PDF for this note could not be found. It may have been removed from the library.',
  not_pdf: 'That file is not a readable PDF.',
  ai_busy: 'The AI service is busy right now. Wait a minute and try again.',
  ai_blocked: 'The AI service declined to process this material. You can still write your own summary, cards or quiz.',
  ai_failed: 'The AI service did not answer. Try again in a moment. Your notes, cards and quizzes still work.',
  ai_video: 'The AI could not watch that video. Check it is public (not private or unlisted) and try again.',
  ai_invalid_output: 'The AI answer was not usable, so nothing was saved. Try again.',
  note_changed: 'The note was edited while the AI was working, so nothing was saved. Try again.',
  server_error: 'Something went wrong on the server. Try again.',
} as const

type Code = keyof typeof MESSAGES

function fail(code: Code, status: number, extra: Record<string, unknown> = {}): Outcome {
  return { status, body: { error: code, message: MESSAGES[code], ...extra } }
}

/** SHA-256 of the PDF's bytes as 64 hex characters. */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return Array.from(digest, (b) => b.toString(16).padStart(2, '0')).join('')
}

export async function run(
  authorization: string | null,
  rawBody: unknown,
  deps: Deps,
): Promise<Outcome> {
  // ---- 1. who is asking?
  const token = authorization?.startsWith('Bearer ') ? authorization.slice(7).trim() : ''
  if (!token) return fail('unauthenticated', 401)
  let userId: string | null
  try {
    userId = await deps.verifyUser(token)
  } catch {
    userId = null
  }
  if (!userId) return fail('unauthenticated', 401)

  // ---- what are they asking for?
  const body = (typeof rawBody === 'object' && rawBody !== null ? rawBody : {}) as Record<string, unknown>
  const kind = body.type as Kind
  const noteId = typeof body.note_id === 'string' ? body.note_id : ''
  if (!KINDS.includes(kind) || !UUID.test(noteId)) return fail('bad_request', 400)

  // ---- 2. daily limit, then the note (only if it is theirs)
  const prepared = await deps.prepare(userId, noteId, kind)
  if (prepared.error) {
    deps.log('refused', { kind, reason: prepared.error })
    switch (prepared.error) {
      case 'limit_reached': return fail('limit_reached', 429, { remaining: 0 })
      case 'project_limit_reached': return fail('project_limit_reached', 429, { remaining: 0 })
      case 'not_student': return fail('not_student', 403)
      case 'not_found': return fail('not_found', 404)
      case 'no_source': return fail('no_source', 422)
      case 'bad_type': return fail('bad_request', 400)
      default: return fail('server_error', 500)
    }
  }
  const title = prepared.title ?? ''
  const noteBody = prepared.body ?? ''

  // ---- 3. input length: the typed text, then the PDF
  if (title.length + noteBody.length > MAX_INPUT_CHARS) {
    deps.log('refused', { kind, reason: 'input_too_long' })
    return fail('input_too_long', 413)
  }
  let pdf: Uint8Array | null = null
  let fileSha = ''
  if (prepared.file_bucket && prepared.file_path) {
    try {
      pdf = await deps.downloadFile(prepared.file_bucket, prepared.file_path, MAX_PDF_BYTES)
    } catch (e) {
      const code: Code = e instanceof FileError ? e.code : 'file_missing'
      deps.log('refused', { kind, reason: code })
      return fail(code, code === 'file_too_large' ? 413 : code === 'not_pdf' ? 415 : 404)
    }
    if (pdf.byteLength > MAX_PDF_BYTES) {
      deps.log('refused', { kind, reason: 'file_too_large' })
      return fail('file_too_large', 413)
    }
    // A real PDF starts with "%PDF-".
    if (!(pdf[0] === 0x25 && pdf[1] === 0x50 && pdf[2] === 0x44 && pdf[3] === 0x46 && pdf[4] === 0x2d)) {
      deps.log('refused', { kind, reason: 'not_pdf' })
      return fail('not_pdf', 415)
    }
    fileSha = await sha256Hex(pdf)
  }
  // A video is fingerprinted by its link, so the cache key changes with it.
  const youtubeUrl = typeof prepared.youtube_url === 'string' && prepared.youtube_url ? prepared.youtube_url : null
  if (youtubeUrl) fileSha = await sha256Hex(new TextEncoder().encode(`youtube:${youtubeUrl}`))

  // ---- 4. cache: this exact content has been done before
  const lookup = await deps.findCache(userId, noteId, kind, fileSha)
  if (lookup.cache_id) {
    const item = await deps.materialise(userId, lookup.cache_id)
    deps.log('cache_hit', { kind, reused: item.reused, pdf: pdf !== null, video: youtubeUrl !== null })
    return {
      status: 200,
      body: { ...item, cached: true, remaining: prepared.remaining ?? 0 },
    }
  }

  // ---- 5. spend one request, then ask Gemini
  const remaining = await deps.consume(userId)
  if (remaining === -1) return fail('limit_reached', 429, { remaining: 0 })
  if (remaining === -2) return fail('project_limit_reached', 429, { remaining: 0 })

  let raw: string
  try {
    raw = await deps.generate(kind, title, noteBody, pdf, youtubeUrl)
  } catch (e) {
    const code: Code = e instanceof ModelError ? e.code : 'ai_failed'
    deps.log('model_error', { kind, code })
    return fail(code, code === 'ai_busy' ? 503 : 502, { remaining })
  }

  // ---- 6. validate before anything is kept
  let result: GeneratedResult
  try {
    result = validateOutput(kind, raw)
  } catch (e) {
    deps.log('invalid_output', { kind, reason: e instanceof InvalidOutput ? e.message : 'unknown' })
    return fail('ai_invalid_output', 502, { remaining })
  }

  // ---- 7. save
  let item: SavedItem
  try {
    item = await deps.store(userId, noteId, kind, lookup.content_hash, result, fileSha)
  } catch (e) {
    const code = e instanceof StoreError ? e.code : 'failed'
    deps.log('store_error', { kind, code })
    if (code === 'note_changed') return fail('note_changed', 409, { remaining })
    if (code === 'invalid') return fail('ai_invalid_output', 502, { remaining })
    return fail('server_error', 500, { remaining })
  }

  // ---- 8. done
  deps.log('generated', { kind, pdf: pdf !== null, video: youtubeUrl !== null })
  return { status: 200, body: { ...item, cached: false, remaining } }
}
