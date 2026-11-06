// ZutLib study-generate: the settings this function owns.
//
// Each value lives here and nowhere else. The daily limits are not here on
// purpose: they are stored in the database (study_ai_daily_limit() and
// study_ai_project_daily_limit() in 0010_study_assistant.sql) so the app
// and this function always agree on them.

// The Gemini model. Checked against https://ai.google.dev/gemini-api/docs/models
// on 22 October 2026: a stable model with a free tier, and one of the two
// the page recommends for new projects. Change it here only.
export const GEMINI_MODEL = 'gemini-3.5-flash-lite'

// The REST endpoint for generateContent, as documented at
// https://ai.google.dev/api/generate-content
export const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`

// The most note text (title plus body, in characters) sent to Gemini in one
// request. About 3,000 tokens of input: enough for a full set of lecture
// notes, small enough to keep each request cheap against the free quota.
export const MAX_INPUT_CHARS = 12000

// The longest answer Gemini may write, in tokens. Generous, because a
// truncated answer is invalid JSON and is thrown away.
export const MAX_OUTPUT_TOKENS = 8192

// A whole study kit (guide, up to 40 cards, up to 30 questions) is a much
// longer answer, so it gets a larger allowance. Output on the free tier
// costs nothing; this only stops a runaway answer.
export const MAX_OUTPUT_TOKENS_KIT = 24576

// A kit is now written in four parts at the same time (guide, flashcards,
// two sets of questions), so a much fuller kit takes about as long as the
// slowest part instead of the sum of them. The guide is the longest.
export const MAX_OUTPUT_TOKENS_GUIDE = 32768
export const MAX_OUTPUT_TOKENS_PART = 16384

// How long to wait for Gemini before giving up, in milliseconds. A PDF can
// take a while to read; Supabase stops a free-plan function that has not
// answered after 150 seconds, so this stays well under that.
export const GEMINI_TIMEOUT_MS = 115000

// The largest PDF sent to Gemini, in bytes (10 MB). Gemini accepts up to
// 50 MB, but a larger file is slow, uses much more of the free quota, and
// is base64-encoded in memory here. Uploads are held to the same size by
// the study-files bucket limit in 0013_study_pdfs.sql.
export const MAX_PDF_BYTES = 10 * 1024 * 1024

// All the PDFs of one kit are sent to Gemini in a single request, whose
// inline data must stay under about 20 MB. A kit may hold 30 MB of PDFs
// (0020_kit_sources.sql), so AI help reads at most this much at once.
export const MAX_TOTAL_PDF_BYTES = 18 * 1024 * 1024
