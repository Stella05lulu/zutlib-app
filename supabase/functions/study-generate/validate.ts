// ZutLib study-generate: checking what Gemini sends back.
//
// The model's answer is treated like any other untrusted input. It must be
// JSON, it must have exactly the fields we asked for and no others, every
// text must be non-empty and within the same length limits the database
// enforces, and every quiz question must have exactly one correct option.
// Anything else is rejected and never stored.

export type Kind = 'summary' | 'flashcards' | 'quiz'
export const KINDS: readonly Kind[] = ['summary', 'flashcards', 'quiz']

export interface SummaryResult { summary: string }
export interface FlashcardsResult { cards: { question: string; answer: string }[] }
export interface QuizOption { text: string; is_correct: boolean }
export interface QuizQuestion { question: string; options: QuizOption[]; explanation?: string }
export interface QuizResult { questions: QuizQuestion[] }
export type GeneratedResult = SummaryResult | FlashcardsResult | QuizResult

// The same limits as the CHECK constraints in 0010_study_assistant.sql.
export const LIMITS = {
  summaryChars: 5000,
  cardsMin: 1, cardsMax: 20, cardQuestionChars: 500, cardAnswerChars: 1000,
  questionsMin: 1, questionsMax: 15, questionChars: 500,
  optionsMin: 2, optionsMax: 6, optionChars: 200, explanationChars: 1000,
} as const

export class InvalidOutput extends Error {}

function fail(reason: string): never {
  throw new InvalidOutput(reason)
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

// The object must have every required key, may have the optional ones,
// and must have nothing else.
function exactKeys(o: Record<string, unknown>, required: string[], optional: string[] = []) {
  for (const k of required) if (!(k in o)) fail(`missing field ${k}`)
  for (const k of Object.keys(o)) {
    if (!required.includes(k) && !optional.includes(k)) fail(`unexpected field ${k}`)
  }
}

function text(v: unknown, field: string, max: number): string {
  if (typeof v !== 'string') fail(`${field} is not text`)
  const t = v.trim()
  if (t.length === 0) fail(`${field} is empty`)
  if (t.length > max) fail(`${field} is too long`)
  return t
}

function list(v: unknown, field: string, min: number, max: number): unknown[] {
  if (!Array.isArray(v)) fail(`${field} is not a list`)
  if (v.length < min || v.length > max) fail(`${field} has ${v.length} items`)
  return v
}

/** Parses and checks the model's raw text. Returns a clean copy (trimmed
 *  strings, no extra fields) or throws InvalidOutput. */
export function validateOutput(kind: Kind, raw: string): GeneratedResult {
  let data: unknown
  try {
    data = JSON.parse(raw)
  } catch {
    fail('not JSON')
  }
  if (!isPlainObject(data)) fail('not a JSON object')

  if (kind === 'summary') {
    exactKeys(data, ['summary'])
    return { summary: text(data.summary, 'summary', LIMITS.summaryChars) }
  }

  if (kind === 'flashcards') {
    exactKeys(data, ['cards'])
    const cards = list(data.cards, 'cards', LIMITS.cardsMin, LIMITS.cardsMax).map((c, i) => {
      if (!isPlainObject(c)) fail(`card ${i} is not an object`)
      exactKeys(c, ['question', 'answer'])
      return {
        question: text(c.question, `card ${i} question`, LIMITS.cardQuestionChars),
        answer: text(c.answer, `card ${i} answer`, LIMITS.cardAnswerChars),
      }
    })
    return { cards }
  }

  exactKeys(data, ['questions'])
  const questions = list(data.questions, 'questions', LIMITS.questionsMin, LIMITS.questionsMax)
    .map((q, i) => {
      if (!isPlainObject(q)) fail(`question ${i} is not an object`)
      exactKeys(q, ['question', 'options'], ['explanation'])
      const options = list(q.options, `question ${i} options`, LIMITS.optionsMin, LIMITS.optionsMax)
        .map((o, j) => {
          if (!isPlainObject(o)) fail(`question ${i} option ${j} is not an object`)
          exactKeys(o, ['text', 'is_correct'])
          if (typeof o.is_correct !== 'boolean') fail(`question ${i} option ${j} is_correct is not true or false`)
          return { text: text(o.text, `question ${i} option ${j}`, LIMITS.optionChars), is_correct: o.is_correct }
        })
      const correct = options.filter((o) => o.is_correct).length
      if (correct !== 1) fail(`question ${i} has ${correct} correct options`)
      const distinct = new Set(options.map((o) => o.text.toLowerCase()))
      if (distinct.size !== options.length) fail(`question ${i} repeats an option`)

      const out: QuizQuestion = {
        question: text(q.question, `question ${i}`, LIMITS.questionChars),
        options,
      }
      if (q.explanation !== undefined && q.explanation !== null) {
        if (typeof q.explanation !== 'string') fail(`question ${i} explanation is not text`)
        const e = q.explanation.trim()
        if (e.length > LIMITS.explanationChars) fail(`question ${i} explanation is too long`)
        if (e.length > 0) out.explanation = e
      }
      return out
    })
  return { questions }
}
