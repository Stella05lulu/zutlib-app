// ZutLib — registration
//
// Eligibility precedes identity. An account cannot be created unless the
// student number is on the institutional roll, the surname matches it, and
// the record has not already been claimed. All three are checked here,
// server side, under the service role. The client never touches the roll.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function fail(code: string, message: string, status = 400) {
  return new Response(JSON.stringify({ error: code, message }), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return fail('method_not_allowed', 'Use POST.', 405)

  let body: Record<string, string>
  try {
    body = await req.json()
  } catch {
    return fail('bad_request', 'Send a JSON body.')
  }

  const studentNumber = (body.student_number ?? '').trim()
  const surname       = (body.surname ?? '').trim()
  const email         = (body.email ?? '').trim().toLowerCase()
  const password      = body.password ?? ''

  if (!studentNumber || !surname || !email || !password) {
    return fail('missing_fields', 'Student number, surname, email and password are all required.')
  }
  if (password.length < 8) {
    return fail('weak_password', 'Use at least 8 characters.')
  }
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return fail('bad_email', 'That email address is not valid.')
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )

  // 1. The number must be on the roll.
  const { data: roll, error: rollErr } = await admin
    .from('roll').select('*').eq('student_number', studentNumber).maybeSingle()

  if (rollErr) return fail('server_error', 'Could not check the student roll.', 500)
  if (!roll) {
    return fail('not_on_roll',
      'That student number is not on the institutional roll. Check it and try again.')
  }

  // 2. The surname must match it. Case and accent insensitive.
  const norm = (s: string) =>
    s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
  if (norm(roll.surname) !== norm(surname)) {
    return fail('surname_mismatch',
      'That surname does not match the record for this student number.')
  }

  // 3. It must not already be claimed.
  if (roll.claimed) {
    return fail('already_claimed',
      'An account already exists for this student number. Try signing in, or reset your password.')
  }

  // Create the account. admin.createUser does NOT send any email, so the
  // verification email is sent explicitly further down, once setup succeeds.
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: false,
    user_metadata: { student_number: studentNumber, surname: roll.surname },
  })

  if (createErr || !created?.user) {
    const msg = (createErr?.message ?? '').toLowerCase()
    if (msg.includes('already registered') || msg.includes('already been registered')) {
      return fail('email_in_use', 'That email address already has an account.')
    }
    return fail('server_error', 'Could not create the account.', 500)
  }

  const uid = created.user.id
  const fullName = [roll.first_name, roll.surname].filter(Boolean).join(' ') || roll.surname

  // Claim the roll record. The partial unique index on claimed_by means a
  // simultaneous second attempt against the same record loses here.
  const { error: claimErr } = await admin
    .from('roll')
    .update({ claimed: true, claimed_by: uid, claimed_at: new Date().toISOString() })
    .eq('student_number', studentNumber)
    .eq('claimed', false)

  if (claimErr) {
    await admin.auth.admin.deleteUser(uid)
    return fail('already_claimed',
      'That student number was claimed a moment ago. If this was not you, contact the library.')
  }

  const { error: profErr } = await admin.from('profiles').insert({
    id: uid,
    full_name: fullName,
    surname: roll.surname,
    student_number: studentNumber,
    programme: roll.programme,
    department: roll.department,
    role: 'student',
  })

  if (profErr) {
    // Unwind so the roll record is not stranded as claimed.
    await admin.from('roll').update({
      claimed: false, claimed_by: null, claimed_at: null,
    }).eq('student_number', studentNumber)
    await admin.auth.admin.deleteUser(uid)
    return fail('server_error', 'Could not finish setting up the account.', 500)
  }

  // Send the verification email. createUser above never sends one.
  const { error: mailErr } = await admin.auth.resend({
    type: 'signup',
    email,
    options: { emailRedirectTo: 'zutlib://login-callback' },
  })
  if (mailErr) console.error('verification email failed:', mailErr.message)

  await admin.from('audit_entries').insert({
    actor_id: uid, action: 'register', target_table: 'profiles', target_id: uid,
    detail: { student_number: studentNumber },
  })

  return new Response(JSON.stringify({
    ok: true,
    message: mailErr
      ? 'Account created, but the verification email could not be sent. Use "Resend verification" on the sign-in screen.'
      : 'Account created. Check your email to verify the address.',
    full_name: fullName,
    programme: roll.programme,
  }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
})
