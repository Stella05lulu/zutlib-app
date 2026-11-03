// ZutLib study-generate: checking what Gemini sends back.
//
// The model's answer is treated like any other untrusted input. It must be
// JSON, it must have exactly the fields we asked for and no others, every
// text must be non-empty and within the same length limits the database
// enforces, and every quiz question must have exactly one correct option.
// Anything else is rejected and never stored.

export type Kind = 'summary' | 'flashcards' | 'quiz' | 'kit'
export const KINDS: readonly Kind[] = ['summary', 'flashcards', 'quiz', 'kit']

export interface SummaryResult { summary: string }
export interface FlashcardsResult { cards: { question: string; answer: string }[] }
export interface QuizOption { text: string; is_correct: boolean }
export interface QuizQuestion { question: string; options: QuizOption[]; explanation?: string }
export interface QuizResult { questions: QuizQuestion[] }
export type Difficulty = 'easy' | 'medium' | 'hard'
export interface GuideSection { heading: string; summary: string; points: string[] }
export interface KitQuestion extends QuizQuestion { difficulty: Difficulty }
/** A whole study kit from one request: a study guide, flashcards (term and
 *  definition, which the matching and true-or-false games also use) and a
 *  question bank for Smart Study and tests. */
export interface KitResult {
  guide: { overview: string; sections: GuideSection[] }
  cards: { term: string; definition: string }[]
  questions: KitQuestion[]
}
export type GeneratedResult = SummaryResult | FlashcardsResult | QuizResult | KitResult

// The same limits as the CHECK constraints in 0010_study_assistant.sql.
export const LIMITS = {
  summaryChars: 5000,
  cardsMin: 1, cardsMax: 20, cardQuestionChars: 500, cardAnswerChars: 1000,
  questionsMin: 1, questionsMax: 15, questionChars: 500,
  optionsMin: 2, optionsMax: 6, optionChars: 200, explanationChars: 1000,
  // A study kit (0014_study_kits.sql)
  overviewChars: 2000, sectionsMin: 1, sectionsMax: 12, headingChars: 160,
  sectionSummaryChars: 1500, pointsMax: 10, pointChars: 300,
  kitCardsMin: 4, kitCardsMax: 40, termChars: 200, definitionChars: 600,
  kitQuestionsMin: 4, kitQuestionsMax: 30,
} as const

const DIFFICULTIES: readonly Difficulty[] = ['easy', 'medium', 'hard']

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

  if (kind === 'kit') return validateKit(data)

  exactKeys(data, ['questions'])
  const questions = list(data.questions, 'questions', LIMITS.questionsMin, LIMITS.questionsMax)
    .map((q, i) => checkQuestion(q, i))
  return { questions }
}

/** One multiple choice question: exactly one correct option, no repeats. */
function checkQuestion(q: unknown, i: number, extra: string[] = []): QuizQuestion {
  if (!isPlainObject(q)) fail(`question ${i} is not an object`)
  exactKeys(q, ['question', 'options'], ['explanation', ...extra])
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
}

function validateKit(data: Record<string, unknown>): KitResult {
  exactKeys(data, ['guide', 'cards', 'questions'])

  const g = data.guide
  if (!isPlainObject(g)) fail('guide is not an object')
  exactKeys(g, ['overview', 'sections'])
  const sections = list(g.sections, 'sections', LIMITS.sectionsMin, LIMITS.sectionsMax).map((sec, i) => {
    if (!isPlainObject(sec)) fail(`section ${i} is not an object`)
    exactKeys(sec, ['heading', 'summary', 'points'])
    if (typeof sec.summary !== 'string') fail(`section ${i} summary is not text`)
    const summary = sec.summary.trim()
    if (summary.length > LIMITS.sectionSummaryChars) fail(`section ${i} summary is too long`)
    const points = list(sec.points, `section ${i} points`, 0, LIMITS.pointsMax)
      .map((p, j) => text(p, `section ${i} point ${j}`, LIMITS.pointChars))
    if (summary.length === 0 && points.length === 0) fail(`section ${i} is empty`)
    return { heading: text(sec.heading, `section ${i} heading`, LIMITS.headingChars), summary, points }
  })
  const guide = { overview: text(g.overview, 'overview', LIMITS.overviewChars), sections }

  const cards = list(data.cards, 'cards', LIMITS.kitCardsMin, LIMITS.kitCardsMax).map((c, i) => {
    if (!isPlainObject(c)) fail(`card ${i} is not an object`)
    exactKeys(c, ['term', 'definition'])
    return {
      term: text(c.term, `card ${i} term`, LIMITS.termChars),
      definition: text(c.definition, `card ${i} definition`, LIMITS.definitionChars),
    }
  })
  // The matching game pairs terms with definitions, so terms must differ.
  if (new Set(cards.map((c) => c.term.toLowerCase())).size !== cards.length) fail('two cards share a term')

  const questions = list(data.questions, 'questions', LIMITS.kitQuestionsMin, LIMITS.kitQuestionsMax)
    .map((q, i) => {
      const base = checkQuestion(q, i, ['difficulty'])
      const d = (q as Record<string, unknown>).difficulty
      if (d !== undefined && !DIFFICULTIES.includes(d as Difficulty)) fail(`question ${i} difficulty is not easy, medium or hard`)
      return { ...base, difficulty: (d ?? 'medium') as Difficulty }
    })

  return { guide, cards, questions }
}
