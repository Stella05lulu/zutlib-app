// Tiny assertion helpers, so the tests need nothing downloaded.

export function assert(cond: unknown, msg = 'assertion failed'): asserts cond {
  if (!cond) throw new Error(msg)
}

export function assertEquals<T>(actual: T, expected: T, msg = '') {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) throw new Error(`${msg}\n  expected: ${e}\n  actual:   ${a}`)
}

export function assertThrows(fn: () => unknown, kind: new (...a: never[]) => Error, msg = '') {
  try {
    fn()
  } catch (e) {
    if (e instanceof kind) return
    throw new Error(`${msg} threw ${(e as Error).name} instead of ${kind.name}`)
  }
  throw new Error(`${msg} did not throw`)
}

export async function assertRejects(
  fn: () => Promise<unknown>,
  check: (e: unknown) => boolean,
  msg = '',
) {
  try {
    await fn()
  } catch (e) {
    if (check(e)) return
    throw new Error(`${msg} rejected with the wrong error: ${e}`)
  }
  throw new Error(`${msg} did not reject`)
}
