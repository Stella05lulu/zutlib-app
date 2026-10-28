// End to end for admin-users against a real local database and PostgREST,
// with a stand-in for Supabase Auth's invite endpoint that creates the user
// in that database (so the sign-up trigger really runs).
//
// Skipped unless STUDY_E2E=1. supabase/tests/local/run_local.sh runs it.

import { run, type Deps } from '../handler.ts'
import { restDeps } from '../rest.ts'
import { assert, assertEquals } from './assert.ts'
import { jwt, PGRST, sql, startGateway } from '../../../tests/local/gateway.ts'

const enabled = Deno.env.get('STUDY_E2E') === '1'

const M = '00000000-0000-4000-8000-0000000008d0'   // admin
const L = '00000000-0000-4000-8000-0000000008c0'   // librarian
const P = '00000000-0000-4000-8000-0000000008a0'   // student who signed up
const PAPER = '00000000-0000-4000-8000-0000000008f1'
const NEW_LIB = 'e2e-new-librarian@example.invalid'
const NEW_STU = 'e2e-new-student@example.invalid'

Deno.test({
  name: 'end to end: admin-users invites, approves and suspends, and refuses everyone else',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn(t) {
    const cleanup = `
      delete from public.audit_entries where actor_id in ('${M}');
      delete from public.profiles where id in ('${M}', '${L}', '${P}')
         or email in ('${NEW_LIB}', '${NEW_STU}', 'e2e-mailtest@example.invalid');
      delete from auth.users where id in ('${M}', '${L}', '${P}')
         or email in ('${NEW_LIB}', '${NEW_STU}', 'e2e-mailtest@example.invalid');
      delete from public.resources where id = '${PAPER}';`
    await sql(cleanup)
    await sql(`
      insert into auth.users (id, email, raw_user_meta_data) values
        ('${M}', 'e2e-admin@example.invalid', '{"full_name":"E2E Admin"}'),
        ('${L}', 'e2e-lib@example.invalid', '{"full_name":"E2E Librarian"}'),
        ('${P}', 'e2e-pending@example.invalid', '{"full_name":"E2E Pending","department":"Business"}');
      update public.profiles set role = 'admin', status = 'active' where id = '${M}';
      update public.profiles set role = 'librarian', status = 'active' where id = '${L}';
      insert into public.resources (id, title, type, department, course_code, academic_year, file_path)
        values ('${PAPER}', 'E2E paper', 'past_paper', 'ICT', 'ICT 1010', 2024, 'x/e2e.pdf');
    `)

    const gw = startGateway()
    const service = await jwt({ role: 'service_role' })
    const deps: Deps = { ...restDeps({ url: gw.url, anonKey: 'anon', serviceKey: service }), log: () => {} }
    const tokenM = await jwt({ sub: M, role: 'authenticated' })
    const tokenL = await jwt({ sub: L, role: 'authenticated' })
    const tokenP = await jwt({ sub: P, role: 'authenticated' })
    const call = (token: string | null, body: Record<string, unknown>) =>
      run(token ? `Bearer ${token}` : null, { redirect_to: 'http://localhost:5000', ...body }, deps)
    const papersSeenBy = async (token: string) => {
      const res = await fetch(`${PGRST}/resources?select=id&id=eq.${PAPER}`, { headers: { Authorization: `Bearer ${token}` } })
      return (await res.json() as unknown[]).length
    }

    try {
      await t.step('signed out and librarian callers are refused, and no email goes out', async () => {
        assertEquals((await call(null, { action: 'create', email: NEW_LIB, full_name: 'X', role: 'librarian' })).status, 401)
        assertEquals((await call(tokenL, { action: 'create', email: NEW_LIB, full_name: 'X', role: 'admin' })).status, 403)
        assertEquals((await call(tokenL, { action: 'approve', user_id: P })).status, 403)
        assertEquals(gw.invites.length, 0)
        assertEquals(await sql(`select count(*) from auth.users where email = '${NEW_LIB}'`), '0')
      })

      await t.step('a pending student sees nothing until approved', async () => {
        assertEquals(await papersSeenBy(tokenP), 0)
      })

      await t.step('the admin approves the student, which is logged, and they can now see papers', async () => {
        const out = await call(tokenM, { action: 'approve', user_id: P })
        assertEquals(out.status, 200)
        assertEquals(await sql(`select status from public.profiles where id = '${P}'`), 'active')
        assertEquals(await sql(`select count(*) from public.audit_entries where action = 'admin.approve' and target_id = '${P}'`), '1')
        assertEquals(await papersSeenBy(tokenP), 1)
      })

      await t.step('the admin suspends the student and access stops', async () => {
        assertEquals((await call(tokenM, { action: 'suspend', user_id: P })).status, 200)
        assertEquals(await papersSeenBy(tokenP), 0)
      })

      await t.step('the admin cannot suspend themselves', async () => {
        const out = await call(tokenM, { action: 'suspend', user_id: M })
        assertEquals(out.status, 403)
      })

      let newLibId = ''
      await t.step('the admin invites a librarian: email sent, role set, approved, password still to choose', async () => {
        const out = await call(tokenM, { action: 'create', email: NEW_LIB, full_name: 'New Librarian', role: 'librarian' })
        assertEquals(out.status, 200)
        assertEquals(gw.invites.at(-1), { email: NEW_LIB, redirectTo: 'http://localhost:5000' })
        newLibId = await sql(`select id from auth.users where email = '${NEW_LIB}'`)
        assertEquals(await sql(`select role || ' ' || status || ' ' || must_set_password from public.profiles where id = '${newLibId}'`),
          'librarian active true')
        assertEquals(await sql(`select count(*) from public.audit_entries where action = 'admin.create' and target_id = '${newLibId}'`), '1')
      })

      await t.step('an invite opened but not finished can be resent as a password link', async () => {
        // Opening the invite confirms the address; the password is not chosen yet.
        await sql(`update auth.users set email_confirmed_at = now() where id = '${newLibId}'`)
        const before = gw.recoveries.length
        const out = await call(tokenM, { action: 'resend_invite', user_id: newLibId })
        assertEquals(out.status, 200)
        assertEquals(gw.recoveries.length, before + 1)
        assertEquals(gw.recoveries[gw.recoveries.length - 1].email, NEW_LIB)
      })

      await t.step('the invited librarian completes setup and is staff', async () => {
        // Supabase confirms the address when the invite link is opened.
        await sql(`update auth.users set email_confirmed_at = now() where id = '${newLibId}'`)
        const token = await jwt({ sub: newLibId, role: 'authenticated' })
        const res = await fetch(`${PGRST}/rpc/mark_password_set`, {
          method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{}',
        })
        assert(res.ok, `mark_password_set ${res.status}`)
        await res.body?.cancel()
        assertEquals(await sql(`select must_set_password from public.profiles where id = '${newLibId}'`), 'f')
        assertEquals(await papersSeenBy(token), 1)
      })

      await t.step('inviting the same address again is refused, and so is resending to someone set up', async () => {
        assertEquals((await call(tokenM, { action: 'create', email: NEW_LIB, full_name: 'Again', role: 'admin' })).status, 409)
        assertEquals((await call(tokenM, { action: 'resend_invite', user_id: newLibId })).status, 409)
        assertEquals(await sql(`select role from public.profiles where id = '${newLibId}'`), 'librarian')
      })

      await t.step('a student invited by the admin is approved straight away; the invite can be resent', async () => {
        const out = await call(tokenM, { action: 'create', email: NEW_STU, full_name: 'New Student', role: 'student', department: 'ICT' })
        assertEquals(out.status, 200)
        const id = await sql(`select id from auth.users where email = '${NEW_STU}'`)
        assertEquals(await sql(`select status || ' ' || department from public.profiles where id = '${id}'`), 'active ICT')
        const before = gw.invites.length
        assertEquals((await call(tokenM, { action: 'resend_invite', user_id: id })).status, 200)
        assertEquals(gw.invites.length, before + 1)
      })

      await t.step('a rate-limited email shows how long to wait', async () => {
        gw.failNextInvite = { status: 429, msg: 'For security purposes, you can only request this after 41 seconds.' }
        const out = await call(tokenM, { action: 'test_invite', email: 'e2e-mailtest@example.invalid' })
        assertEquals(out.status, 429)
        assertEquals(out.body.retry_after, 41)
      })

      await t.step('a test invite makes a suspended account that can do nothing', async () => {
        const out = await call(tokenM, { action: 'test_invite', email: 'e2e-mailtest@example.invalid' })
        assertEquals(out.status, 200)
        assertEquals(await sql(`select status || ' ' || full_name from public.profiles where email = 'e2e-mailtest@example.invalid'`),
          'suspended Email test')
      })

      await t.step('nobody can change their own role or status through the API', async () => {
        for (const [token, id] of [[tokenP, P], [tokenL, L], [tokenM, M]]) {
          const res = await fetch(`${PGRST}/profiles?id=eq.${id}`, {
            method: 'PATCH',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ role: 'admin', status: 'active' }),
          })
          assert(!res.ok, `PATCH by ${id} was accepted`)
          await res.body?.cancel()
        }
        assertEquals(await sql(`select role || ' ' || status from public.profiles where id = '${P}'`), 'student suspended')
        assertEquals(await sql(`select role from public.profiles where id = '${L}'`), 'librarian')
      })

      await t.step('nobody but the service role can call the admin functions', async () => {
        const res = await fetch(`${PGRST}/rpc/admin_apply`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${tokenM}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_actor: M, p_target: P, p_action: 'reactivate' }),
        })
        assert(!res.ok, 'admin_apply was callable with a user token')
        await res.body?.cancel()
      })
    } finally {
      await gw.close()
      await sql(cleanup)
    }
  },
})
