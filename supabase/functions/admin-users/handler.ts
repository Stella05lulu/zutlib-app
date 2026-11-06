// ZutLib admin-users: everything an administrator does to accounts.
//
// Every request runs these steps first, in this order:
//   1. verify the caller's sign-in token            -> 401 if not signed in
//   2. confirm the caller is an ACTIVE administrator -> 403 for everyone else
// Only then is the action looked at:
//
//   create         invite a new student, librarian or admin by email. The
//                  person gets Supabase's invite email and chooses their own
//                  password; nobody else ever sees or sets one. The account
//                  is approved straight away with the chosen role.
//   test_invite    send an invite to an address to check email delivery.
//                  The account it makes is suspended, so it can do nothing.
//   resend_invite  send the invite again to someone who has not set up yet.
//   approve, reject, suspend, reactivate, set_role, remove
//                  change an existing account (database function
//                  admin_apply, which also writes the audit log). An
//                  optional reason is stored in the audit entry.
//
// Super admin account tools (reason required, audited by the database):
//   edit_profile         name, department and student number
//   change_email         Auth changes the address, then a password link
//                        goes to the new one
//   password_link        a link to choose a new password; nobody else ever
//                        sees or sets a password
//   sign_out_everywhere  ends every sign-in session
//   restore              a removed account becomes active again
//
// Roles rank student < librarian < admin < super admin, and everyone acts
// only on accounts below their own. Only a super admin may invite an
// administrator, change a role or remove an account; nobody can make a
// super admin here. The database enforces all of this again
// (0017_super_admin.sql); the checks below only stop an invite email from
// going out for a request the database would refuse.
//
// Database and Auth calls are passed in as `deps`, so the tests run every
// path without a real server.

export type Role = 'student' | 'librarian' | 'admin'
const ROLES: Role[] = ['student', 'librarian', 'admin']
const DEPARTMENTS = ['ICT', 'Engineering', 'Business']
const STATUS_ACTIONS = ['approve', 'reject', 'suspend', 'reactivate', 'set_role', 'remove', 'restore'] as const
const SUPER_TOOLS = ['edit_profile', 'change_email', 'password_link', 'sign_out_everywhere'] as const
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

/** A failure from Supabase Auth, with its HTTP status. */
export class AuthApiError extends Error {
  constructor(public status: number, public apiCode: string, message: string) {
    super(message)
  }
}

/** A failure from a database function, with its Postgres error code. */
export class DbError extends Error {
  constructor(public pgCode: string, message: string) {
    super(message)
  }
}

export interface AuthUser {
  id: string
  email: string
  confirmed: boolean
}

export interface Deps {
  verifyUser(token: string): Promise<string | null>
  isAdmin(userId: string): Promise<boolean>
  isSuperAdmin(userId: string): Promise<boolean>
  /** True when actor is an active admin or super admin ranked above target. */
  canManage(actor: string, target: string): Promise<boolean>
  /** Sends Supabase's invite email; creates the user if they do not exist. */
  invite(email: string, data: Record<string, string>, redirectTo: string | null): Promise<AuthUser>
  getUser(userId: string): Promise<AuthUser | null>
  /** True while an invited person has not chosen their password yet. */
  needsPassword(userId: string): Promise<boolean>
  /** Sends Supabase's password email, for an invite that was opened but
   *  never finished (the invite email cannot be sent twice once opened). */
  sendSetupLink(email: string, redirectTo: string | null): Promise<void>
  afterInvite(actor: string, user: string, role: Role, fullName: string,
              department: string | null, test: boolean): Promise<Record<string, unknown>>
  apply(actor: string, target: string, action: string, role: Role | null,
        reason: string | null): Promise<Record<string, unknown>>
  record(actor: string, action: string, target: string, detail: Record<string, unknown>): Promise<void>
  editProfile(actor: string, target: string, fullName: string, department: string | null,
              studentNumber: string | null, reason: string): Promise<Record<string, unknown>>
  /** Audits a super admin tool whose work happens in Auth; throws DbError if refused. */
  superRecord(actor: string, target: string, action: string, reason: string,
              detail: Record<string, unknown>): Promise<void>
  revokeSessions(actor: string, target: string, reason: string): Promise<number>
  /** Changes a user's address in Auth, already confirmed. */
  updateEmail(userId: string, email: string): Promise<void>
  log(event: string, fields?: Record<string, string | number | boolean>): void
}

export interface Outcome {
  status: number
  body: Record<string, unknown>
}

function fail(status: number, error: string, message: string, extra: Record<string, unknown> = {}): Outcome {
  return { status, body: { error, message, ...extra } }
}

/** Supabase says "For security purposes, you can only request this after
 *  42 seconds." when an email to the same person is sent too soon. */
export function retryAfterSeconds(message: string): number {
  const m = /after (\d+) second/i.exec(message)
  return m ? Number(m[1]) : 60
}

function authFailure(e: AuthApiError): Outcome {
  if (e.status === 429) {
    const wait = retryAfterSeconds(e.message)
    return fail(429, 'rate_limited',
      `Too many emails were sent just now. You can send again in ${wait} seconds.`,
      { retry_after: wait })
  }
  if (e.status === 422 && /already|exists|registered/i.test(e.message + e.apiCode)) {
    return fail(409, 'already_registered', 'An account with this email address already exists.')
  }
  return fail(502, 'email_failed', `The invite email could not be sent: ${e.message}`)
}

function dbFailure(e: DbError): Outcome {
  if (e.pgCode === '42501') return fail(403, 'forbidden', e.message)
  if (e.pgCode === 'P0002') return fail(404, 'not_found', e.message)
  if (e.pgCode === '22023') return fail(409, 'not_allowed', e.message)
  return fail(500, 'server_error', 'Something went wrong on the server. Try again.')
}

/** Only addresses the app itself uses may be the target of an invite link. */
function safeRedirect(v: unknown): string | null {
  return typeof v === 'string' && /^(https?:\/\/|zutlib:\/\/)[^\s]+$/.test(v) && v.length < 300 ? v : null
}

export async function run(authorization: string | null, rawBody: unknown, deps: Deps): Promise<Outcome> {
  // ---- 1. who is asking?
  const token = authorization?.startsWith('Bearer ') ? authorization.slice(7).trim() : ''
  if (!token) return fail(401, 'unauthenticated', 'Sign in again.')
  let actor: string | null = null
  try {
    actor = await deps.verifyUser(token)
  } catch {
    actor = null
  }
  if (!actor) return fail(401, 'unauthenticated', 'Sign in again.')

  // ---- 2. only an active administrator gets any further
  if (!(await deps.isAdmin(actor))) {
    deps.log('forbidden', {})
    return fail(403, 'forbidden', 'Only an administrator can manage accounts.')
  }

  const body = (typeof rawBody === 'object' && rawBody !== null ? rawBody : {}) as Record<string, unknown>
  const action = typeof body.action === 'string' ? body.action : ''
  const redirectTo = safeRedirect(body.redirect_to)

  try {
    // ------------------------------------------------ create
    if (action === 'create' || action === 'test_invite') {
      const test = action === 'test_invite'
      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
      if (!EMAIL.test(email) || email.length > 200) {
        return fail(400, 'bad_email', 'That email address is not valid.')
      }
      const role = (test ? 'student' : body.role) as Role
      if (!ROLES.includes(role)) return fail(400, 'bad_role', 'Choose student, librarian or admin.')
      const fullName = test ? 'Email test' : typeof body.full_name === 'string' ? body.full_name.trim() : ''
      if (fullName.length < 2 || fullName.length > 120) {
        return fail(400, 'bad_name', 'Enter the person\'s full name.')
      }
      const department = typeof body.department === 'string' && DEPARTMENTS.includes(body.department)
        ? body.department : null
      if (role === 'admin' && !(await deps.isSuperAdmin(actor))) {
        return fail(403, 'forbidden', 'Only a super admin can create an administrator.')
      }
      if (role === 'student' && !test && !department) {
        return fail(400, 'bad_department', 'Choose the student\'s department: ICT, Engineering or Business.')
      }

      const user = await deps.invite(email, { full_name: fullName, ...(department ? { department } : {}) }, redirectTo)
      if (user.confirmed) {
        return fail(409, 'already_registered', 'An account with this email address already exists.')
      }
      const profile = await deps.afterInvite(actor, user.id, role, fullName, department, test)
      deps.log(test ? 'test_invite_sent' : 'invite_sent', { role })
      return {
        status: 200,
        body: {
          ok: true,
          message: test
            ? `Test invite sent to ${email}. Check that inbox (and its spam folder).`
            : `Invite sent to ${email}. They will choose their own password from the email.`,
          profile,
        },
      }
    }

    // ------------------------------------------------ resend
    if (action === 'resend_invite') {
      const target = typeof body.user_id === 'string' ? body.user_id : ''
      if (!UUID.test(target)) return fail(400, 'bad_request', 'Choose an account.')
      if (!(await deps.canManage(actor, target))) {
        return fail(403, 'forbidden', 'You can only manage accounts below your own role.')
      }
      const user = await deps.getUser(target)
      if (!user) return fail(404, 'not_found', 'That account no longer exists.')
      if (user.confirmed) {
        if (!await deps.needsPassword(target)) {
          return fail(409, 'already_set_up', 'This person has already set up their account, so there is no invite to resend.')
        }
        // They opened the invite but never chose a password: send a link to
        // choose one instead, which Supabase allows for a confirmed address.
        await deps.sendSetupLink(user.email, redirectTo)
        await deps.record(actor, 'resend_invite', target, { email: user.email, kind: 'password_link' })
        deps.log('setup_link_sent', {})
        return { status: 200, body: { ok: true, message: `A link to choose a password was sent to ${user.email}.` } }
      }
      await deps.invite(user.email, {}, redirectTo)
      await deps.record(actor, 'resend_invite', target, { email: user.email })
      deps.log('invite_resent', {})
      return { status: 200, body: { ok: true, message: `Invite sent again to ${user.email}.` } }
    }

    // ------------------------------------------------ super admin tools
    if ((SUPER_TOOLS as readonly string[]).includes(action)) {
      if (!(await deps.isSuperAdmin(actor))) {
        return fail(403, 'forbidden', 'Only a super admin can do that.')
      }
      const target = typeof body.user_id === 'string' ? body.user_id : ''
      if (!UUID.test(target)) return fail(400, 'bad_request', 'Choose an account.')
      const reason = typeof body.reason === 'string' ? body.reason.trim().slice(0, 500) : ''
      if (reason.length < 3) return fail(400, 'reason_required', 'Give a reason. It is kept in the audit log.')

      if (action === 'edit_profile') {
        const fullName = typeof body.full_name === 'string' ? body.full_name : ''
        const department = typeof body.department === 'string' && body.department ? body.department : null
        const number = typeof body.student_number === 'string' && body.student_number.trim()
          ? body.student_number : null
        const profile = await deps.editProfile(actor, target, fullName, department, number, reason)
        deps.log('profile_edited', {})
        return { status: 200, body: { ok: true, profile, message: 'The account details were saved.' } }
      }

      if (action === 'sign_out_everywhere') {
        const n = await deps.revokeSessions(actor, target, reason)
        deps.log('sessions_revoked', { sessions: n })
        return {
          status: 200,
          body: { ok: true, sessions: n, message: 'Signed out everywhere. Each device must sign in again within the hour.' },
        }
      }

      const user = await deps.getUser(target)
      if (!user) return fail(404, 'not_found', 'That account no longer exists.')

      if (action === 'change_email') {
        const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
        if (!EMAIL.test(email) || email.length > 200) return fail(400, 'bad_email', 'That email address is not valid.')
        if (email === user.email.toLowerCase()) return fail(409, 'not_allowed', 'That is already their email address.')
        // Audited (and checked) first, so a refused request never reaches Auth.
        await deps.superRecord(actor, target, 'change_email', reason, { from: user.email, to: email })
        await deps.updateEmail(target, email)
        await deps.sendSetupLink(email, redirectTo)
        deps.log('email_changed', {})
        return { status: 200, body: { ok: true, message: `Email changed. A link to choose a password was sent to ${email}.` } }
      }

      // password_link
      await deps.superRecord(actor, target, 'password_link', reason, {})
      await deps.sendSetupLink(user.email, redirectTo)
      deps.log('password_link_sent', {})
      return { status: 200, body: { ok: true, message: `A link to choose a new password was sent to ${user.email}.` } }
    }

    // ------------------------------------------------ status and role
    if ((STATUS_ACTIONS as readonly string[]).includes(action)) {
      const target = typeof body.user_id === 'string' ? body.user_id : ''
      if (!UUID.test(target)) return fail(400, 'bad_request', 'Choose an account.')
      let role: Role | null = null
      if (action === 'set_role') {
        role = body.role as Role
        if (!ROLES.includes(role)) return fail(400, 'bad_role', 'Choose student, librarian or admin.')
      }
      const reason = typeof body.reason === 'string' && body.reason.trim() ? body.reason.trim().slice(0, 500) : null
      const profile = await deps.apply(actor, target, action, role, reason)
      deps.log('account_changed', { action })
      return { status: 200, body: { ok: true, profile } }
    }

    return fail(400, 'bad_action', 'That is not a known action.')
  } catch (e) {
    if (e instanceof AuthApiError) {
      deps.log('auth_error', { action, status: e.status })
      return authFailure(e)
    }
    if (e instanceof DbError) {
      deps.log('db_error', { action, code: e.pgCode })
      return dbFailure(e)
    }
    deps.log('server_error', { action })
    return fail(500, 'server_error', 'Something went wrong on the server. Try again.')
  }
}
