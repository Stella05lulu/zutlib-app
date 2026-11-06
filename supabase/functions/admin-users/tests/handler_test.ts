// admin-users with stand-ins for Supabase Auth and the database. Each
// stand-in counts its calls, so the tests prove, for example, that a
// librarian's request never reaches the invite step.
//
//   deno test supabase/functions/admin-users/tests/

import { AuthApiError, DbError, type Deps, retryAfterSeconds, run } from '../handler.ts'
import { assert, assertEquals } from './assert.ts'

const ADMIN = '00000000-0000-4000-8000-00000000ad01'
const LIB = '00000000-0000-4000-8000-00000000ad02'
const TARGET = '00000000-0000-4000-8000-00000000ad03'
const SUPER = '00000000-0000-4000-8000-00000000ad04'

function fake(overrides: Partial<Deps> = {}) {
  const calls: Record<string, number> = {}
  const seen: Record<string, unknown[]> = {}
  const count = (name: string, args: unknown[]) => {
    calls[name] = (calls[name] ?? 0) + 1
    seen[name] = args
  }
  const base: Deps = {
    verifyUser: (t) =>
      Promise.resolve(t === 'admin-token' ? ADMIN : t === 'lib-token' ? LIB : t === 'super-token' ? SUPER : null),
    isAdmin: (id) => Promise.resolve(id === ADMIN || id === SUPER),
    isSuperAdmin: (id) => Promise.resolve(id === SUPER),
    canManage: () => Promise.resolve(true),
    invite: (email) => Promise.resolve({ id: TARGET, email, confirmed: false }),
    getUser: () => Promise.resolve({ id: TARGET, email: 'new@zut.test', confirmed: false }),
    needsPassword: () => Promise.resolve(false),
    sendSetupLink: () => Promise.resolve(),
    afterInvite: (_a, user, role) => Promise.resolve({ id: user, role, status: 'active' }),
    apply: (_a, target, action) => Promise.resolve({ id: target, status: action === 'approve' ? 'active' : 'x' }),
    record: () => Promise.resolve(),
    editProfile: (_a, t, fullName) => Promise.resolve({ id: t, full_name: fullName }),
    superRecord: () => Promise.resolve(),
    revokeSessions: () => Promise.resolve(2),
    updateEmail: () => Promise.resolve(),
    log: () => {},
  }
  const merged = { ...base, ...overrides } as Deps
  const wrapped = {} as Record<string, unknown>
  for (const [k, fn] of Object.entries(merged)) {
    wrapped[k] = (...a: unknown[]) => { count(k, a); return (fn as (...x: unknown[]) => unknown)(...a) }
  }
  return Object.assign(wrapped as unknown as Deps, { calls, seen })
}

const create = { action: 'create', email: 'New.Librarian@ZUT.test', full_name: 'New Librarian', role: 'librarian',
  redirect_to: 'http://localhost:5000' }

Deno.test('no token: 401 and nothing else happens', async () => {
  const d = fake()
  const out = await run(null, create, d)
  assertEquals(out.status, 401)
  assertEquals(d.calls.isAdmin, undefined)
  assertEquals(d.calls.invite, undefined)
})

Deno.test('a forged token: 401', async () => {
  const d = fake()
  assertEquals((await run('Bearer forged', create, d)).status, 401)
})

Deno.test('a librarian cannot create accounts: 403 before any invite', async () => {
  const d = fake()
  const out = await run('Bearer lib-token', create, d)
  assertEquals(out.status, 403)
  assertEquals(d.calls.invite, undefined)
  assertEquals(d.calls.afterInvite, undefined)
})

Deno.test('a librarian cannot approve students: 403', async () => {
  const d = fake()
  const out = await run('Bearer lib-token', { action: 'approve', user_id: TARGET }, d)
  assertEquals(out.status, 403)
  assertEquals(d.calls.apply, undefined)
})

Deno.test('an admin creates a librarian: invite sent, role set server-side, no password anywhere', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', create, d)
  assertEquals(out.status, 200)
  const [email, data, redirect] = d.seen.invite as [string, Record<string, string>, string]
  assertEquals(email, 'new.librarian@zut.test')
  assertEquals(redirect, 'http://localhost:5000')
  assert(!('password' in data), 'no password is sent')
  assert(!('role' in data), 'the role is not put in user-editable metadata')
  const [actor, user, role, , , test] = d.seen.afterInvite as [string, string, string, string, string, boolean]
  assertEquals([actor, user, role, test], [ADMIN, TARGET, 'librarian', false])
  assert(!JSON.stringify(out.body).toLowerCase().includes('password":'), 'no password is returned')
})

Deno.test('a student needs a department', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', { ...create, role: 'student' }, d)
  assertEquals(out.status, 400)
  assertEquals(d.calls.invite, undefined)
})

Deno.test('an unknown role is refused', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', { ...create, role: 'superuser' }, d)
  assertEquals(out.status, 400)
})

Deno.test('a bad email is refused before Auth is called', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', { ...create, email: 'not-an-email' }, d)
  assertEquals(out.status, 400)
  assertEquals(d.calls.invite, undefined)
})

Deno.test('an unsafe redirect is dropped', async () => {
  const d = fake()
  await run('Bearer admin-token', { ...create, redirect_to: 'javascript:alert(1)' }, d)
  assertEquals((d.seen.invite as unknown[])[2], null)
})

Deno.test('an address that already has an account: 409', async () => {
  const d = fake({ invite: () => Promise.reject(new AuthApiError(422, 'email_exists', 'A user with this email address has already been registered')) })
  const out = await run('Bearer admin-token', create, d)
  assertEquals(out.status, 409)
  assertEquals(out.body.error, 'already_registered')
})

Deno.test('rate limited by Supabase: 429 with the seconds to wait', async () => {
  const d = fake({ invite: () => Promise.reject(new AuthApiError(429, 'over_email_send_rate_limit', 'For security purposes, you can only request this after 37 seconds.')) })
  const out = await run('Bearer admin-token', create, d)
  assertEquals(out.status, 429)
  assertEquals(out.body.retry_after, 37)
  assert(String(out.body.message).includes('37 seconds'), 'the wait is in the message')
})

Deno.test('rate limit with no seconds in the message defaults to 60', () => {
  assertEquals(retryAfterSeconds('email rate limit exceeded'), 60)
  assertEquals(retryAfterSeconds('only request this after 1 second'), 1)
})

Deno.test('the SMTP server failing: a clear 502', async () => {
  const d = fake({ invite: () => Promise.reject(new AuthApiError(500, 'unexpected_failure', 'Error sending invite email')) })
  const out = await run('Bearer admin-token', create, d)
  assertEquals(out.status, 502)
  assert(String(out.body.message).includes('Error sending invite email'), 'the reason is shown to the admin')
})

Deno.test('a test invite makes a suspended student called "Email test"', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', { action: 'test_invite', email: 'me@zut.test' }, d)
  assertEquals(out.status, 200)
  const [, , role, name, , test] = d.seen.afterInvite as [string, string, string, string, string, boolean]
  assertEquals([role, name, test], ['student', 'Email test', true])
})

Deno.test('resend: refused when the person already set up', async () => {
  const d = fake({ getUser: () => Promise.resolve({ id: TARGET, email: 'a@zut.test', confirmed: true }) })
  const out = await run('Bearer admin-token', { action: 'resend_invite', user_id: TARGET }, d)
  assertEquals(out.status, 409)
  assertEquals(d.calls.invite, undefined)
})

Deno.test('resend: an invite opened but not finished gets a password link instead', async () => {
  const d = fake({
    getUser: () => Promise.resolve({ id: TARGET, email: 'a@zut.test', confirmed: true }),
    needsPassword: () => Promise.resolve(true),
  })
  const out = await run('Bearer admin-token', { action: 'resend_invite', user_id: TARGET, redirect_to: 'http://localhost:5000' }, d)
  assertEquals(out.status, 200)
  assertEquals(d.calls.invite, undefined)
  assertEquals(d.seen.sendSetupLink, ['a@zut.test', 'http://localhost:5000'])
  assert(String(out.body.message).includes('choose a password'), 'says what was sent')
})

Deno.test('resend: sent again and logged', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', { action: 'resend_invite', user_id: TARGET }, d)
  assertEquals(out.status, 200)
  assertEquals(d.calls.invite, 1)
  assertEquals((d.seen.record as unknown[])[1], 'resend_invite')
})

Deno.test('approve goes through the audited database function', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', { action: 'approve', user_id: TARGET }, d)
  assertEquals(out.status, 200)
  assertEquals(d.seen.apply, [ADMIN, TARGET, 'approve', null, null])
})

Deno.test('set_role passes the role and checks it', async () => {
  const d = fake()
  assertEquals((await run('Bearer admin-token', { action: 'set_role', user_id: TARGET, role: 'god' }, d)).status, 400)
  await run('Bearer admin-token', { action: 'set_role', user_id: TARGET, role: 'admin' }, d)
  assertEquals(d.seen.apply, [ADMIN, TARGET, 'set_role', 'admin', null])
})

Deno.test('the database refusing (for example acting on yourself) becomes a plain 403', async () => {
  const d = fake({ apply: () => Promise.reject(new DbError('42501', 'You cannot change your own account. Ask another administrator.')) })
  const out = await run('Bearer admin-token', { action: 'suspend', user_id: ADMIN }, d)
  assertEquals(out.status, 403)
  assert(String(out.body.message).includes('your own account'), 'message passed through')
})

Deno.test('an unknown action: 400', async () => {
  const d = fake()
  assertEquals((await run('Bearer admin-token', { action: 'delete_everything' }, d)).status, 400)
})

// ---------------------------------------------------------------- super admin

Deno.test('an admin cannot create an administrator: 403 before any invite', async () => {
  const d = fake()
  const out = await run('Bearer admin-token', { ...create, role: 'admin' }, d)
  assertEquals(out.status, 403)
  assertEquals(d.calls.invite, undefined)
  assertEquals(d.calls.afterInvite, undefined)
})

Deno.test('a super admin creates an administrator', async () => {
  const d = fake()
  const out = await run('Bearer super-token', { ...create, role: 'admin' }, d)
  assertEquals(out.status, 200)
  const [actor, , role] = d.seen.afterInvite as [string, string, string]
  assertEquals([actor, role], [SUPER, 'admin'])
})

Deno.test('nobody can create a super admin: 400 before any invite', async () => {
  const d = fake()
  const out = await run('Bearer super-token', { ...create, role: 'super_admin' }, d)
  assertEquals(out.status, 400)
  assertEquals(d.calls.invite, undefined)
})

Deno.test('nobody can set the super admin role: 400 before the database', async () => {
  const d = fake()
  const out = await run('Bearer super-token', { action: 'set_role', user_id: TARGET, role: 'super_admin' }, d)
  assertEquals(out.status, 400)
  assertEquals(d.calls.apply, undefined)
})

Deno.test('resend to an account at or above your rank: 403 before any email', async () => {
  const d = fake({ canManage: () => Promise.resolve(false) })
  const out = await run('Bearer admin-token', { action: 'resend_invite', user_id: TARGET }, d)
  assertEquals(out.status, 403)
  assertEquals(d.calls.invite, undefined)
  assertEquals(d.calls.sendSetupLink, undefined)
  assertEquals(d.calls.record, undefined)
})

Deno.test('remove passes the reason to the audited database function', async () => {
  const d = fake()
  const out = await run('Bearer super-token', { action: 'remove', user_id: TARGET, reason: '  Left the college  ' }, d)
  assertEquals(out.status, 200)
  assertEquals(d.seen.apply, [SUPER, TARGET, 'remove', null, 'Left the college'])
})

Deno.test('an admin removing someone is refused by the database: 403', async () => {
  const d = fake({ apply: () => Promise.reject(new DbError('42501', 'Only a super admin can do that.')) })
  const out = await run('Bearer admin-token', { action: 'remove', user_id: TARGET }, d)
  assertEquals(out.status, 403)
  assertEquals(out.body.message, 'Only a super admin can do that.')
})

// ---------------------------------------------------------------- account tools

Deno.test('an admin cannot use the super admin tools: 403, nothing reaches Auth or the database', async () => {
  for (const action of ['edit_profile', 'change_email', 'password_link', 'sign_out_everywhere']) {
    const d = fake()
    const out = await run('Bearer admin-token', { action, user_id: TARGET, reason: 'Because', email: 'x@zut.test' }, d)
    assertEquals(out.status, 403, action)
    assertEquals(d.calls.updateEmail, undefined)
    assertEquals(d.calls.sendSetupLink, undefined)
    assertEquals(d.calls.superRecord, undefined)
    assertEquals(d.calls.revokeSessions, undefined)
    assertEquals(d.calls.editProfile, undefined)
  }
})

Deno.test('a librarian cannot use the account tools: 403', async () => {
  const d = fake()
  const out = await run('Bearer lib-token', { action: 'password_link', user_id: TARGET, reason: 'Because' }, d)
  assertEquals(out.status, 403)
  assertEquals(d.calls.sendSetupLink, undefined)
})

Deno.test('every account tool needs a reason', async () => {
  const d = fake()
  const out = await run('Bearer super-token', { action: 'sign_out_everywhere', user_id: TARGET, reason: ' ' }, d)
  assertEquals(out.status, 400)
  assertEquals(out.body.error, 'reason_required')
  assertEquals(d.calls.revokeSessions, undefined)
})

Deno.test('change email: audited first, then Auth, then a password link to the new address', async () => {
  const order: string[] = []
  const d = fake({
    superRecord: () => { order.push('record'); return Promise.resolve() },
    updateEmail: () => { order.push('auth'); return Promise.resolve() },
    sendSetupLink: (email) => { order.push(`link:${email}`); return Promise.resolve() },
  })
  const out = await run('Bearer super-token',
    { action: 'change_email', user_id: TARGET, reason: 'Typo at sign-up', email: 'Right@ZUT.test' }, d)
  assertEquals(out.status, 200)
  assertEquals(order, ['record', 'auth', 'link:right@zut.test'])
})

Deno.test('change email refused by the database never reaches Auth', async () => {
  const d = fake({ superRecord: () => Promise.reject(new DbError('42501', 'You can only manage accounts below your own role.')) })
  const out = await run('Bearer super-token',
    { action: 'change_email', user_id: TARGET, reason: 'Typo', email: 'right@zut.test' }, d)
  assertEquals(out.status, 403)
  assertEquals(d.calls.updateEmail, undefined)
  assertEquals(d.calls.sendSetupLink, undefined)
})

Deno.test('password link goes to the account address and returns no password', async () => {
  const d = fake()
  const out = await run('Bearer super-token', { action: 'password_link', user_id: TARGET, reason: 'Forgot it' }, d)
  assertEquals(out.status, 200)
  assertEquals((d.seen.sendSetupLink as unknown[])[0], 'new@zut.test')
  assert(!JSON.stringify(out.body).toLowerCase().includes('password":'), 'no password is returned')
})

Deno.test('sign out everywhere and edit profile go through the audited database functions', async () => {
  const d = fake()
  assertEquals((await run('Bearer super-token', { action: 'sign_out_everywhere', user_id: TARGET, reason: 'Lost phone' }, d)).status, 200)
  assertEquals(d.seen.revokeSessions, [SUPER, TARGET, 'Lost phone'])
  const out = await run('Bearer super-token',
    { action: 'edit_profile', user_id: TARGET, reason: 'Name spelling', full_name: 'Ama Banda', department: 'ICT', student_number: '' }, d)
  assertEquals(out.status, 200)
  assertEquals(d.seen.editProfile, [SUPER, TARGET, 'Ama Banda', 'ICT', null, 'Name spelling'])
})

Deno.test('restore goes through admin_apply with its reason', async () => {
  const d = fake()
  const out = await run('Bearer super-token', { action: 'restore', user_id: TARGET, reason: 'Removed by mistake' }, d)
  assertEquals(out.status, 200)
  assertEquals(d.seen.apply, [SUPER, TARGET, 'restore', null, 'Removed by mistake'])
})
