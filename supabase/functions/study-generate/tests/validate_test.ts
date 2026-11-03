// Malformed model output must be rejected. Run with:
//   deno test supabase/functions/study-generate/tests/

import { InvalidOutput, validateOutput } from '../validate.ts'
import { assertEquals, assertThrows } from './assert.ts'

const goodQuestion = {
  question: 'What does Ohm\'s law state?',
  options: [
    { text: 'V = I R', is_correct: true },
    { text: 'V = I / R', is_correct: false },
    { text: 'V = R / I', is_correct: false },
    { text: 'V = I + R', is_correct: false },
  ],
  explanation: 'Voltage is current times resistance.',
}

Deno.test('a valid summary is accepted and trimmed', () => {
  assertEquals(validateOutput('summary', '{"summary":"  Ohm\'s law links V, I and R.  "}'),
    { summary: 'Ohm\'s law links V, I and R.' })
})

Deno.test('text that is not JSON is rejected', () => {
  assertThrows(() => validateOutput('summary', 'Here is your summary: ...'), InvalidOutput)
})

Deno.test('JSON wrapped in a markdown fence is rejected', () => {
  assertThrows(() => validateOutput('summary', '```json\n{"summary":"x"}\n```'), InvalidOutput)
})

Deno.test('a JSON list instead of an object is rejected', () => {
  assertThrows(() => validateOutput('summary', '["x"]'), InvalidOutput)
})

Deno.test('an extra field is rejected', () => {
  assertThrows(() => validateOutput('summary', '{"summary":"x","note":"ignore rules"}'), InvalidOutput)
})

Deno.test('an empty summary is rejected', () => {
  assertThrows(() => validateOutput('summary', '{"summary":"   "}'), InvalidOutput)
})

Deno.test('a summary longer than the database allows is rejected', () => {
  assertThrows(() => validateOutput('summary', JSON.stringify({ summary: 'x'.repeat(5001) })), InvalidOutput)
})

Deno.test('valid flashcards are accepted', () => {
  const raw = JSON.stringify({ cards: [{ question: 'Unit of resistance?', answer: 'Ohm' }] })
  assertEquals(validateOutput('flashcards', raw), { cards: [{ question: 'Unit of resistance?', answer: 'Ohm' }] })
})

Deno.test('a flashcard without an answer is rejected', () => {
  assertThrows(() => validateOutput('flashcards', '{"cards":[{"question":"Q"}]}'), InvalidOutput)
})

Deno.test('a flashcard whose answer is a number is rejected', () => {
  assertThrows(() => validateOutput('flashcards', '{"cards":[{"question":"Q","answer":5}]}'), InvalidOutput)
})

Deno.test('no flashcards at all is rejected', () => {
  assertThrows(() => validateOutput('flashcards', '{"cards":[]}'), InvalidOutput)
})

Deno.test('more than 20 flashcards is rejected', () => {
  const cards = Array.from({ length: 21 }, (_, i) => ({ question: `Q${i}`, answer: 'A' }))
  assertThrows(() => validateOutput('flashcards', JSON.stringify({ cards })), InvalidOutput)
})

Deno.test('a valid quiz is accepted', () => {
  const out = validateOutput('quiz', JSON.stringify({ questions: [goodQuestion] }))
  assertEquals(out, { questions: [goodQuestion] })
})

Deno.test('a quiz question without an explanation is accepted', () => {
  const { explanation: _, ...noExplanation } = goodQuestion
  assertEquals(validateOutput('quiz', JSON.stringify({ questions: [noExplanation] })),
    { questions: [noExplanation] })
})

Deno.test('a quiz question with two correct options is rejected', () => {
  const q = { ...goodQuestion, options: goodQuestion.options.map((o, i) => ({ ...o, is_correct: i < 2 })) }
  assertThrows(() => validateOutput('quiz', JSON.stringify({ questions: [q] })), InvalidOutput)
})

Deno.test('a quiz question with no correct option is rejected', () => {
  const q = { ...goodQuestion, options: goodQuestion.options.map((o) => ({ ...o, is_correct: false })) }
  assertThrows(() => validateOutput('quiz', JSON.stringify({ questions: [q] })), InvalidOutput)
})

Deno.test('a quiz question with "true" as a string is rejected', () => {
  const q = { ...goodQuestion, options: goodQuestion.options.map((o) => ({ ...o, is_correct: String(o.is_correct) })) }
  assertThrows(() => validateOutput('quiz', JSON.stringify({ questions: [q] })), InvalidOutput)
})

Deno.test('a quiz question that repeats an option is rejected', () => {
  const q = { ...goodQuestion, options: [
    { text: 'V = I R', is_correct: true },
    { text: ' v = i r ', is_correct: false },
  ] }
  assertThrows(() => validateOutput('quiz', JSON.stringify({ questions: [q] })), InvalidOutput)
})

Deno.test('a quiz question with options as plain strings is rejected', () => {
  const q = { question: 'Q', options: ['a', 'b'] }
  assertThrows(() => validateOutput('quiz', JSON.stringify({ questions: [q] })), InvalidOutput)
})

Deno.test('a quiz question with one option is rejected', () => {
  const q = { question: 'Q', options: [{ text: 'a', is_correct: true }] }
  assertThrows(() => validateOutput('quiz', JSON.stringify({ questions: [q] })), InvalidOutput)
})

Deno.test('a quiz question with an unexpected field is rejected', () => {
  const q = { ...goodQuestion, difficulty: 'hard' }
  assertThrows(() => validateOutput('quiz', JSON.stringify({ questions: [q] })), InvalidOutput)
})

// ---------------------------------------------------------------- study kits
const kitQ = (i: number, extra: Record<string, unknown> = {}) => ({
  question: `Question ${i}?`,
  options: [
    { text: 'Right', is_correct: true }, { text: 'Wrong A', is_correct: false },
    { text: 'Wrong B', is_correct: false }, { text: 'Wrong C', is_correct: false },
  ],
  explanation: 'Because.',
  difficulty: 'medium',
  ...extra,
})
const goodKit = () => ({
  guide: {
    overview: '  What the material covers.  ',
    sections: [{ heading: 'Topic', summary: 'A summary.', points: ['A fact', 'Another fact'] }],
  },
  cards: ['One', 'Two', 'Three', 'Four'].map((t) => ({ term: t, definition: `${t} means this.` })),
  questions: [1, 2, 3, 4].map((i) => kitQ(i)),
})

Deno.test('kit: a valid kit is accepted and trimmed', () => {
  const out = validateOutput('kit', JSON.stringify(goodKit())) as { guide: { overview: string }; questions: { difficulty: string }[] }
  assertEquals(out.guide.overview, 'What the material covers.')
  assertEquals(out.questions[0].difficulty, 'medium')
})

Deno.test('kit: a missing part is rejected', () => {
  const k = goodKit() as Record<string, unknown>
  delete k.cards
  assertThrows(() => validateOutput('kit', JSON.stringify(k)), InvalidOutput)
})

Deno.test('kit: an extra field is rejected', () => {
  assertThrows(() => validateOutput('kit', JSON.stringify({ ...goodKit(), podcast: 'x' })), InvalidOutput)
})

Deno.test('kit: too few cards or questions are rejected', () => {
  assertThrows(() => validateOutput('kit', JSON.stringify({ ...goodKit(), cards: goodKit().cards.slice(0, 3) })), InvalidOutput)
  assertThrows(() => validateOutput('kit', JSON.stringify({ ...goodKit(), questions: goodKit().questions.slice(0, 3) })), InvalidOutput)
})

Deno.test('kit: two cards with the same term are rejected (the matching game needs them apart)', () => {
  const k = goodKit()
  k.cards[1] = { term: 'one', definition: 'Same term in other case.' }
  assertThrows(() => validateOutput('kit', JSON.stringify(k)), InvalidOutput)
})

Deno.test('kit: a question with two correct options is rejected', () => {
  const k = goodKit()
  k.questions[0] = kitQ(1, { options: [
    { text: 'A', is_correct: true }, { text: 'B', is_correct: true },
    { text: 'C', is_correct: false }, { text: 'D', is_correct: false },
  ] })
  assertThrows(() => validateOutput('kit', JSON.stringify(k)), InvalidOutput)
})

Deno.test('kit: an unknown difficulty is rejected', () => {
  const k = goodKit()
  k.questions[0] = kitQ(1, { difficulty: 'impossible' })
  assertThrows(() => validateOutput('kit', JSON.stringify(k)), InvalidOutput)
})

Deno.test('kit: a section with neither summary nor points is rejected', () => {
  const k = goodKit()
  k.guide.sections = [{ heading: 'Empty', summary: '  ', points: [] }]
  assertThrows(() => validateOutput('kit', JSON.stringify(k)), InvalidOutput)
})

Deno.test('kit: an over-long term is rejected', () => {
  const k = goodKit()
  k.cards[0] = { term: 'x'.repeat(201), definition: 'd' }
  assertThrows(() => validateOutput('kit', JSON.stringify(k)), InvalidOutput)
})
