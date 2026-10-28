-- ZutLib: first administrator (and backup demo accounts), one time
--
-- There are no default accounts or passwords in this repository. The first
-- administrator is made like this, once:
--
--   1. Supabase dashboard -> Authentication -> Users -> Add user ->
--      Create new user. Enter YOUR email and a strong password you choose,
--      tick "Auto Confirm User".
--   2. Put that email in the list below (replace admin@example.com), then
--      SQL Editor -> New query -> paste this file -> Run.
--
-- After that, sign in to the app as that administrator and create every
-- other account from Admin -> Users -> Create account, which sends an
-- invite email so each person sets their own password.
--
-- Backup accounts for the demo (one approved student, one librarian, one
-- admin, made the day before): either invite them from the app, or create
-- them in step 1 the same way and add their emails below with the role
-- they need. Running this file again is safe; it only sets role and status.

with wanted (email, role, department) as (values
     ('namonjestella@gmail.com', 'admin', null)
  -- , ('backup.librarian@example.com', 'librarian', null)
  -- , ('backup.student@example.com',   'student',   'ICT')
)
update public.profiles p
   set role = w.role::user_role,
       status = 'active',
       department = coalesce(w.department, p.department),
       decided_at = now()
  from wanted w
  join auth.users u on lower(u.email) = lower(w.email)
 where p.id = u.id;

-- Check: every email above should be listed, active, with its role. An
-- email that is missing here was not created in step 1.
select u.email, p.full_name, p.role, p.status
from public.profiles p join auth.users u on u.id = p.id
where p.role in ('admin', 'librarian') or p.status = 'active'
order by p.role, u.email;
