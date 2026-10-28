// Every step of the pipeline with stand-ins for the database and Gemini.
// Each stand-in counts its calls, so the tests can prove, for example,
// that a cache hit never reaches Gemini and a bad answer is never stored.

import { type Deps, FileError, run, sha256Hex, StoreError } from '../pipeline.ts'
import { ModelError } from '../gemini.ts'
import { MAX_INPUT_CHARS, MAX_PDF_BYTES } from '../config.ts'
import { assert, assertEquals } from './assert.ts'

const USER = '00000000-0000-4000-8000-0000000000a1'
const NOTE = '00000000-0000-4000-8000-0000000000b1'
const SECRET_TEXT = 'Ohm law private note text'
const HASH = 'a'.repeat(64)
// The first bytes of any PDF, then some content.
const PDF = new TextEncoder().encode('%PDF-1.4\n' + SECRET_TEXT + '\n%%EOF')

interface Fake extends Deps {
  calls: Record<string, number>
  logs: string[]
}

function fake(overrides: Partial<Deps> = {}): Fake {
  const calls: Record<string, number> = {}
  const logs: string[] = []
  const count = (name: string) => { calls[name] = (calls[name] ?? 0) + 1 }
  const base: Deps = {
    verifyUser: (t) => { count('verifyUser'); return Promise.resolve(t === 'good-token' ? USER : null) },
    prepare: () => {
      count('prepare')
      return Promise.resolve({ title: 'Circuits', body: SECRET_TEXT, content_hash: HASH, remaining: 10 })
    },
    downloadFile: () => { count('downloadFile'); return Promise.resolve(PDF) },
    findCache: () => { count('findCache'); return Promise.resolve({ content_hash: HASH, cache_id: null }) },
    materialise: () => { count('materialise'); return Promise.resolve({ kind: 'summary', id: 'cached-item', reused: true }) },
    consume: () => { count('consume'); return Promise.resolve(9) },
    generate: () => { count('generate'); return Promise.resolve('{"summary":"Voltage is current times resistance."}') },
    store: () => { count('store'); return Promise.resolve({ kind: 'summary', id: 'new-item', reused: false }) },
    log: (event, fields) => logs.push(JSON.stringify({ event, ...fields })),
  }
  const merged = { ...base, ...overrides }
  // Overrides still get counted.
  for (const key of Object.keys(overrides) as (keyof Deps)[]) {
    const fn = overrides[key] as (...a: unknown[]) => unknown
    if (key !== 'log') {
      // deno-lint-ignore no-explicit-any
      (merged as any)[key] = (...a: unknown[]) => { count(key); return fn(...a) }
    }
  }
  return Object.assign(merged, { calls, logs })
}

const request = { type: 'summary', note_id: NOTE }

Deno.test('no sign-in token: refused with 401 before anything else', async () => {
  const d = fake()
  const out = await run(null, request, d)
  assertEquals(out.status, 401)
  assertEquals(out.body.error, 'unauthenticated')
  assertEquals(d.calls.prepare, undefined)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('an invalid or expired token: refused with 401', async () => {
  const d = fake()
  const out = await run('Bearer forged-token', request, d)
  assertEquals(out.status, 401)
  assertEquals(d.calls.verifyUser, 1)
  assertEquals(d.calls.prepare, undefined)
})

Deno.test('an unknown request type: refused with 400', async () => {
  const d = fake()
  const out = await run('Bearer good-token', { type: 'essay', note_id: NOTE }, d)
  assertEquals(out.status, 400)
  assertEquals(d.calls.prepare, undefined)
})

Deno.test('daily limit used up: refused with 429, Gemini never called', async () => {
  const d = fake({ prepare: () => Promise.resolve({ error: 'limit_reached', remaining: 0 }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 429)
  assertEquals(out.body.error, 'limit_reached')
  assertEquals(out.body.remaining, 0)
  assertEquals(d.calls.generate, undefined)
  assertEquals(d.calls.consume, undefined)
})

Deno.test('limit used up by a request racing this one: refused with 429 at the consume step', async () => {
  const d = fake({ consume: () => Promise.resolve(-1) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 429)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('project-wide limit used up: refused with 429', async () => {
  const d = fake({ prepare: () => Promise.resolve({ error: 'project_limit_reached', remaining: 0 }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 429)
  assertEquals(out.body.error, 'project_limit_reached')
})

Deno.test('someone else\'s note (or a deleted one): 404', async () => {
  const d = fake({ prepare: () => Promise.resolve({ error: 'not_found' }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 404)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('a staff account: 403', async () => {
  const d = fake({ prepare: () => Promise.resolve({ error: 'not_student' }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 403)
})

Deno.test('over-length input: refused with 413, no allowance spent, Gemini never called', async () => {
  const long = 'x'.repeat(MAX_INPUT_CHARS)
  const d = fake({ prepare: () => Promise.resolve({ title: 'T', body: long, content_hash: HASH, remaining: 10 }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 413)
  assertEquals(out.body.error, 'input_too_long')
  assertEquals(d.calls.findCache, undefined)
  assertEquals(d.calls.consume, undefined)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('input exactly at the cap is allowed', async () => {
  const body = 'x'.repeat(MAX_INPUT_CHARS - 1)
  const d = fake({ prepare: () => Promise.resolve({ title: 'T', body, content_hash: HASH, remaining: 10 }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 200)
})

Deno.test('cache hit: answered from the cache, Gemini not called, allowance not spent', async () => {
  const d = fake({ findCache: () => Promise.resolve({ content_hash: HASH, cache_id: 'cache-1' }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 200)
  assertEquals(out.body.cached, true)
  assertEquals(out.body.id, 'cached-item')
  assertEquals(d.calls.materialise, 1)
  assertEquals(d.calls.generate, undefined)
  assertEquals(d.calls.consume, undefined)
  assertEquals(d.calls.store, undefined)
})

Deno.test('malformed model output: 502 and nothing stored', async () => {
  const d = fake({ generate: () => Promise.resolve('Sure! Here is a summary: Ohm...') })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 502)
  assertEquals(out.body.error, 'ai_invalid_output')
  assertEquals(d.calls.store, undefined)
})

Deno.test('a quiz with two correct options from the model: 502 and nothing stored', async () => {
  const bad = JSON.stringify({ questions: [{ question: 'Q', options: [
    { text: 'a', is_correct: true }, { text: 'b', is_correct: true },
  ] }] })
  const d = fake({ generate: () => Promise.resolve(bad) })
  const out = await run('Bearer good-token', { type: 'quiz', note_id: NOTE }, d)
  assertEquals(out.status, 502)
  assertEquals(d.calls.store, undefined)
})

Deno.test('the database refusing the shape is also reported as unusable output', async () => {
  const d = fake({ store: () => Promise.reject(new StoreError('invalid', 'constraint 23514')) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 502)
  assertEquals(out.body.error, 'ai_invalid_output')
})

Deno.test('note edited while Gemini worked: 409 and nothing stored', async () => {
  const d = fake({ store: () => Promise.reject(new StoreError('note_changed', 'changed')) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 409)
})

Deno.test('Gemini busy: a clear 503 with the requests left', async () => {
  const d = fake({ generate: () => Promise.reject(new ModelError('ai_busy', '429')) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 503)
  assertEquals(out.body.error, 'ai_busy')
  assertEquals(out.body.remaining, 9)
  assert(typeof out.body.message === 'string' && (out.body.message as string).length > 0, 'message')
})

Deno.test('Gemini down: a clear 502', async () => {
  const d = fake({ generate: () => Promise.reject(new Error('anything')) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 502)
  assertEquals(out.body.error, 'ai_failed')
})

Deno.test('success: validated result stored once and returned with the requests left', async () => {
  let stored: unknown = null
  const d = fake({
    generate: () => Promise.resolve('{"summary":"  Voltage is current times resistance.  "}'),
    store: (_u, _n, _k, _h, result) => { stored = result; return Promise.resolve({ kind: 'summary', id: 'new-item', reused: false }) },
  })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 200)
  assertEquals(out.body, { kind: 'summary', id: 'new-item', reused: false, cached: false, remaining: 9 })
  assertEquals(stored, { summary: 'Voltage is current times resistance.' })
  assertEquals(d.calls.store, 1)
  assertEquals(d.calls.generate, 1)
  assertEquals(d.calls.consume, 1)
})

Deno.test('steps run in the required order', async () => {
  const order: string[] = []
  const step = <T>(name: string, value: T) => () => { order.push(name); return Promise.resolve(value) }
  const d = fake({
    verifyUser: step('auth', USER),
    prepare: step('limit+note', { title: 'T', body: 'b', content_hash: HASH, remaining: 5 }),
    findCache: step('cache', { content_hash: HASH, cache_id: null }),
    consume: step('spend', 4),
    generate: step('gemini', '{"summary":"s"}'),
    store: step('save', { kind: 'summary' as const, id: 'i', reused: false }),
  })
  await run('Bearer good-token', request, d)
  assertEquals(order, ['auth', 'limit+note', 'cache', 'spend', 'gemini', 'save'])
})

Deno.test('logs never contain the note text', async () => {
  for (const generate of [
    () => Promise.resolve('{"summary":"ok"}'),
    () => Promise.resolve('not json ' + SECRET_TEXT),
    () => Promise.reject(new ModelError('ai_failed', 'x')),
  ]) {
    const d = fake({ generate })
    await run('Bearer good-token', request, d)
    for (const line of d.logs) assert(!line.includes(SECRET_TEXT), `note text leaked into a log: ${line}`)
  }
})

// ------------------------------------------------------------- PDFs

const pdfNote = { title: 'Lecture 3', body: '', remaining: 10, file_bucket: 'study-files', file_path: 'u/lecture-3.pdf' }

Deno.test('a PDF note: the PDF is fetched, fingerprinted and sent to Gemini', async () => {
  let sentPdf: Uint8Array | null = null
  let shaUsed = ''
  let storedSha = ''
  const d = fake({
    prepare: () => Promise.resolve(pdfNote),
    findCache: (_u, _n, _k, sha) => { shaUsed = sha; return Promise.resolve({ content_hash: HASH, cache_id: null }) },
    generate: (_k, _t, _b, pdf) => { sentPdf = pdf; return Promise.resolve('{"summary":"From the PDF."}') },
    store: (_u, _n, _k, _h, _r, sha) => { storedSha = sha; return Promise.resolve({ kind: 'summary', id: 'p1', reused: false }) },
  })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 200)
  assertEquals(d.calls.downloadFile, 1)
  assert(sentPdf === PDF, 'the downloaded bytes reach Gemini')
  assertEquals(shaUsed, await sha256Hex(PDF))
  assertEquals(storedSha, shaUsed)
})

Deno.test('a typed note: nothing is downloaded and the fingerprint is empty', async () => {
  let shaUsed = 'unset'
  const d = fake({
    findCache: (_u, _n, _k, sha) => { shaUsed = sha; return Promise.resolve({ content_hash: HASH, cache_id: null }) },
  })
  await run('Bearer good-token', request, d)
  assertEquals(d.calls.downloadFile, undefined)
  assertEquals(shaUsed, '')
})

Deno.test('a PDF over the size cap: 413, no allowance spent, Gemini never called', async () => {
  const d = fake({
    prepare: () => Promise.resolve(pdfNote),
    downloadFile: () => Promise.reject(new FileError('file_too_large', 'big')),
  })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 413)
  assertEquals(out.body.error, 'file_too_large')
  assertEquals(d.calls.consume, undefined)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('a download that is bigger than declared is still refused', async () => {
  const d = fake({
    prepare: () => Promise.resolve(pdfNote),
    downloadFile: () => Promise.resolve(new Uint8Array(MAX_PDF_BYTES + 1)),
  })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 413)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('a file that is not really a PDF: 415, Gemini never called', async () => {
  const d = fake({
    prepare: () => Promise.resolve(pdfNote),
    downloadFile: () => Promise.resolve(new TextEncoder().encode('MZ this is an exe')),
  })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 415)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('a library PDF that has gone: 404 with a plain message', async () => {
  const d = fake({
    prepare: () => Promise.resolve({ ...pdfNote, file_bucket: 'resources' }),
    downloadFile: () => Promise.reject(new FileError('file_missing', '404')),
  })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 404)
  assertEquals(out.body.error, 'file_missing')
})

Deno.test('a note with nothing to study: 422', async () => {
  const d = fake({ prepare: () => Promise.resolve({ error: 'no_source' }) })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.status, 422)
  assertEquals(d.calls.generate, undefined)
})

Deno.test('the same PDF again is a cache hit: no Gemini call', async () => {
  const d = fake({
    prepare: () => Promise.resolve(pdfNote),
    findCache: () => Promise.resolve({ content_hash: HASH, cache_id: 'c9' }),
  })
  const out = await run('Bearer good-token', request, d)
  assertEquals(out.body.cached, true)
  assertEquals(d.calls.generate, undefined)
  assertEquals(d.calls.consume, undefined)
})

Deno.test('logs never contain the PDF content', async () => {
  const d = fake({ prepare: () => Promise.resolve(pdfNote) })
  await run('Bearer good-token', request, d)
  for (const line of d.logs) assert(!line.includes(SECRET_TEXT), `PDF text leaked into a log: ${line}`)
})
