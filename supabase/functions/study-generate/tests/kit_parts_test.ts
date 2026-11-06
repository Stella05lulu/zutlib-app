// A study kit is written in four parts at the same time (guide, cards and
// two sets of questions) and joined into one result. fetch is replaced, so
// nothing here reaches the network.

import { callGemini, mergeKitParts, ModelError } from '../gemini.ts'
import { validateOutput } from '../validate.ts'
import { assert, assertEquals, assertRejects } from './assert.ts'

const answer = (obj: unknown) => ({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify(obj) }] } }] })

const q = (text: string, difficulty = 'easy') => ({
  question: text,
  options: [
    { text: 'Right', is_correct: true }, { text: 'Wrong 1', is_correct: false },
    { text: 'Wrong 2', is_correct: false }, { text: 'Wrong 3', is_correct: false },
  ],
  explanation: 'Because.',
  difficulty,
})

const GUIDE = { overview: 'Covers clouds.', sections: [{ heading: 'Clouds', summary: 'Clouds are servers.', points: ['A point'] }] }
const CARDS = { cards: [1, 2, 3, 4, 5].map((i) => ({ term: `Term ${i}`, definition: `Meaning ${i}` })) }

/** Answers each part by spotting its task text; can make one part fail. */
function partsFetch(fail: string[] = [], seen: string[] = []) {
  return ((_url: string, init?: RequestInit) => {
    const body = JSON.parse(String(init!.body))
    const task = body.contents[0].parts.at(-1).text as string
    const part = task.includes('study guide') ? 'guide'
      : task.includes('flashcards') ? 'cards'
      : task.includes('hard university') ? 'reasoning' : 'recall'
    seen.push(part)
    if (fail.includes(part)) return Promise.resolve(new Response('{}', { status: 500 }))
    const out = part === 'guide' ? GUIDE
      : part === 'cards' ? CARDS
      : part === 'recall' ? { questions: [q('What is a cloud?'), q('What is IaaS?', 'medium'), q('What is PaaS?'), q('What is SaaS?')] }
      : { questions: [q('What is a cloud ?', 'hard'), q('Pick the best design.', 'hard'), q('Plan a migration.', 'hard')] }
    return Promise.resolve(new Response(JSON.stringify(answer(out)), { status: 200 }))
  }) as unknown as typeof fetch
}

Deno.test('a kit is asked for in four parts at once and joined into a valid kit', async () => {
  const seen: string[] = []
  const raw = await callGemini('k', 'kit', 'Cloud', '', [new Uint8Array([37, 80, 68, 70, 45])], partsFetch([], seen))
  assertEquals(seen.sort(), ['cards', 'guide', 'reasoning', 'recall'])
  const kit = validateOutput('kit', raw) as { cards: unknown[]; questions: { question: string }[] }
  assertEquals(kit.cards.length, 5)
  // "What is a cloud ?" repeats "What is a cloud?" and is dropped.
  assertEquals(kit.questions.length, 6)
})

Deno.test('one set of questions may fail if the other arrives', async () => {
  const raw = await callGemini('k', 'kit', 'Cloud', 'notes', null, partsFetch(['reasoning']))
  const kit = validateOutput('kit', raw) as { questions: unknown[] }
  assertEquals(kit.questions.length, 4)
})

Deno.test('without the guide there is no kit', async () => {
  await assertRejects(() => callGemini('k', 'kit', 'Cloud', 'notes', null, partsFetch(['guide'])), (e) => e instanceof ModelError)
})

Deno.test('without the cards there is no kit', async () => {
  await assertRejects(() => callGemini('k', 'kit', 'Cloud', 'notes', null, partsFetch(['cards'])), (e) => e instanceof ModelError)
})

Deno.test('joining trims over-long text and drops repeated terms instead of failing', () => {
  const long = 'x'.repeat(5000)
  const raw = mergeKitParts(
    { overview: long, sections: [{ heading: 'H', summary: long, points: Array(20).fill('p') }] },
    { cards: [...CARDS.cards, { term: 'term 1', definition: 'again' }] },
    [{ questions: [q('Only one?'), q('Two?'), q('Three?'), q('Four?')] }],
  )
  const kit = validateOutput('kit', raw) as {
    guide: { overview: string; sections: { summary: string; points: string[] }[] }; cards: unknown[]
  }
  assert(kit.guide.overview.length <= 2000, 'overview trimmed')
  assert(kit.guide.sections[0].summary.length <= 3000, 'summary trimmed')
  assertEquals(kit.guide.sections[0].points.length, 12)
  assertEquals(kit.cards.length, 5)
})

Deno.test('a broken question is dropped on its own; the rest of the kit is kept', () => {
  const bad = [
    { ...q('Two right answers?'), options: [{ text: 'A', is_correct: true }, { text: 'B', is_correct: true }] },
    { ...q('No right answer?'), options: [{ text: 'A', is_correct: false }, { text: 'B', is_correct: false }] },
    { ...q('One option?'), options: [{ text: 'A', is_correct: true }] },
    { ...q('Repeated options?'), options: [{ text: 'Same', is_correct: true }, { text: 'same', is_correct: false }] },
    { question: '', options: q('x').options },
  ]
  const raw = mergeKitParts(GUIDE, CARDS, [{ questions: [...bad, q('Good 1'), q('Good 2', 'Medium'), q('Good 3', 'HARD'), q('Good 4', 'odd')] }])
  const kit = validateOutput('kit', raw) as { questions: { question: string; difficulty: string }[] }
  assertEquals(kit.questions.map((x) => x.question), ['Good 1', 'Good 2', 'Good 3', 'Good 4'])
  assertEquals(kit.questions.map((x) => x.difficulty), ['easy', 'medium', 'hard', 'medium'])
})

Deno.test('empty cards and sections are dropped, and a missing overview is filled in', () => {
  const raw = mergeKitParts(
    { sections: [{ heading: '', summary: 'No heading' }, { heading: 'Empty', summary: '', points: [] }, ...GUIDE.sections] },
    { cards: [{ term: 'No definition', definition: '' }, ...CARDS.cards] },
    [{ questions: [q('A?'), q('B?'), q('C?'), q('D?')] }],
    'Cloud',
  )
  const kit = validateOutput('kit', raw) as { guide: { overview: string; sections: unknown[] }; cards: unknown[] }
  assertEquals(kit.guide.sections.length, 1)
  assertEquals(kit.cards.length, 5)
  assert(kit.guide.overview.length > 0, 'overview filled in')
})

Deno.test('a part that fails is asked for once more', async () => {
  let cardCalls = 0
  const base = partsFetch()
  const flaky = ((url: string, init?: RequestInit) => {
    const task = JSON.parse(String(init!.body)).contents[0].parts.at(-1).text as string
    if (task.includes('flashcards') && cardCalls++ === 0) return Promise.resolve(new Response('{}', { status: 500 }))
    return base(url, init)
  }) as unknown as typeof fetch
  const raw = await callGemini('k', 'kit', 'Cloud', 'notes', null, flaky)
  assertEquals(cardCalls, 2)
  assertEquals((validateOutput('kit', raw) as { cards: unknown[] }).cards.length, 5)
})

Deno.test('if the model refuses the thinking setting, the part is asked again without it', async () => {
  const base = partsFetch()
  let refused = 0
  const picky = ((url: string, init?: RequestInit) => {
    const body = JSON.parse(String(init!.body))
    if (body.generationConfig.thinkingConfig) {
      refused++
      return Promise.resolve(new Response('{}', { status: 400 }))
    }
    return base(url, init)
  }) as unknown as typeof fetch
  const raw = await callGemini('k', 'kit', 'Cloud', 'notes', null, picky)
  assertEquals(refused, 4)
  validateOutput('kit', raw)
})

Deno.test('with several PDFs the guide is written in two halves at once and joined in order', async () => {
  const pdf = new Uint8Array([37, 80, 68, 70, 45])
  const guideFiles: number[] = []
  const base = partsFetch()
  const counting = ((url: string, init?: RequestInit) => {
    const body = JSON.parse(String(init!.body))
    const parts = body.contents[0].parts
    if ((parts.at(-1).text as string).includes('study guide')) {
      guideFiles.push(parts.filter((p: Record<string, unknown>) => 'inlineData' in p).length)
    }
    return base(url, init)
  }) as unknown as typeof fetch
  const raw = await callGemini('k', 'kit', 'Cloud', '', [pdf, pdf, pdf], counting)
  assertEquals(guideFiles.sort(), [1, 2])
  const kit = validateOutput('kit', raw) as { guide: { sections: unknown[] } }
  // Both halves answered with one section each (sections share a heading, both are kept).
  assertEquals(kit.guide.sections.length, 2)
})
