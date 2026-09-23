// ZutLib — borrowing state transitions
//
// A state change is a server operation. The client asks; this function
// decides. Every transition is validated against the current state before
// anything is written, the copy count moves inside the same statement as
// the status, and every decision leaves an audit record.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type Action = 'review' | 'approve' | 'reject' | 'collect' | 'return';

// The only transitions that exist.
const LEGAL: Record<Action, string[]> = {
  review:  ['submitted'],
  approve: ['submitted', 'under_review'],
  reject:  ['submitted', 'under_review'],
  collect: ['approved'],
  return:  ['collected'],
}

const DEFAULT_LOAN_DAYS = 14

function fail(code: string, message: string, status = 400) {
  return new Response(JSON.stringify({ error: code, message }), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return fail('method_not_allowed', 'Use POST.', 405)

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return fail('unauthenticated', 'Sign in first.', 401)
  }

  const url = Deno.env.get('SUPABASE_URL')!
  const anon = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  })
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  const { data: { user }, error: userErr } = await anon.auth.getUser()
  if (userErr || !user) return fail('unauthenticated', 'Sign in first.', 401)

  const { data: actor } = await admin
    .from('profiles').select('id, role, full_name').eq('id', user.id).maybeSingle()

  if (!actor) return fail('no_profile', 'This account has no profile.', 403)
  if (actor.role !== 'librarian' && actor.role !== 'admin') {
    return fail('forbidden', 'Only library staff can decide borrowing requests.', 403)
  }

  let body: Record<string, string>
  try { body = await req.json() } catch { return fail('bad_request', 'Send a JSON body.') }

  const requestId = (body.request_id ?? '').trim()
  const action = (body.action ?? '').trim() as Action
  const reason = (body.reason ?? '').trim()

  if (!requestId) return fail('missing_fields', 'A request id is required.')
  if (!(action in LEGAL)) return fail('bad_action', 'That is not a known action.')
  if (action === 'reject' && !reason) {
    return fail('reason_required', 'A rejection has to say why.')
  }

  const { data: reqRow } = await admin
    .from('borrow_requests').select('*').eq('id', requestId).maybeSingle()
  if (!reqRow) return fail('not_found', 'That request no longer exists.', 404)

  if (!LEGAL[action].includes(reqRow.status)) {
    return fail('illegal_transition',
      `A request that is ${reqRow.status.replace('_', ' ')} cannot be ${action}ed.`, 409)
  }

  const now = new Date().toISOString()
  const patch: Record<string, unknown> = {}

  if (action === 'review') {
    patch.status = 'under_review'

  } else if (action === 'approve') {
    // Reserve a copy. The guard on available_copies means two staff
    // approving the last copy at once cannot both succeed.
    const { data: reserved, error: resErr } = await admin.rpc('reserve_copy', {
      p_resource: reqRow.resource_id,
    })
    if (resErr) return fail('server_error', 'Could not reserve a copy.', 500)
    if (reserved === false) {
      return fail('no_copies', 'There are no copies available to reserve.', 409)
    }
    patch.status = 'approved'
    patch.decided_by = actor.id
    patch.decided_at = now

  } else if (action === 'reject') {
    patch.status = 'rejected'
    patch.decided_by = actor.id
    patch.decided_at = now
    patch.rejection_reason = reason

  } else if (action === 'collect') {
    const due = new Date()
    due.setDate(due.getDate() + DEFAULT_LOAN_DAYS)
    patch.status = 'collected'
    patch.collected_at = now
    patch.due_date = due.toISOString().slice(0, 10)

  } else if (action === 'return') {
    patch.status = 'returned'
    patch.returned_at = now
    await admin.rpc('release_copy', { p_resource: reqRow.resource_id })
  }

  const { data: updated, error: updErr } = await admin
    .from('borrow_requests')
    .update(patch)
    .eq('id', requestId)
    .eq('status', reqRow.status)   // optimistic: nobody moved it meanwhile
    .select()
    .maybeSingle()

  if (updErr || !updated) {
    if (action === 'approve') await admin.rpc('release_copy', { p_resource: reqRow.resource_id })
    return fail('conflict', 'Someone else updated this request. Reload and try again.', 409)
  }

  await admin.from('audit_entries').insert({
    actor_id: actor.id,
    action: `borrow.${action}`,
    target_table: 'borrow_requests',
    target_id: requestId,
    detail: { from: reqRow.status, to: patch.status, reason: reason || null },
  })

  // In-app notification. The email itself is sent by the auth/SMTP layer
  // or by a database webhook on this table.
  const titles: Record<string, string> = {
    approve: 'Borrowing request approved',
    reject:  'Borrowing request rejected',
    collect: 'Item collected',
    return:  'Item returned',
    review:  'Request under review',
  }
  const bodies: Record<string, string> = {
    approve: `Your request was approved. Collect it from the library.`,
    reject:  `Your request was rejected. Reason: ${reason}`,
    collect: `You collected this item. It is due back on ${patch.due_date}.`,
    return:  'Thanks, this item is back on the shelf.',
    review:  'A librarian is reviewing your request.',
  }

  await admin.from('notifications').insert({
    user_id: reqRow.student_id,
    subject: titles[action],
    body: bodies[action],
  })

  return new Response(JSON.stringify({ ok: true, request: updated }), {
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
})
