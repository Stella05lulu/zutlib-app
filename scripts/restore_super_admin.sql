-- ZutLib: restore a super admin (break glass)
--
-- The app can never make a super admin, and sign-up always makes a pending
-- student. This script is the only way to make one. Use it:
--   - once, to make the first super admin after migrations 0016 and 0017
--   - if the only super admin is locked out or leaves
--
-- HOW TO RUN
--   1. The person must already have a ZutLib account with a confirmed email.
--   2. Supabase -> SQL Editor -> New query -> paste this whole file.
--   3. Change the address on the line marked "CHANGE THIS".
--   4. Run. The result says who is now the super admin.
--
-- It turns "break glass" on for this one transaction only, makes the
-- account an active super admin, and writes the change to the audit log
-- with no actor (it came from the dashboard, not from a person in the app).

begin;

select set_config('zutlib.break_glass', 'on', true);

do $$
declare
    target_email text := 'namonjestella@gmail.com';   -- CHANGE THIS
  p public.profiles;
begin
  if lower(btrim(target_email)) = 'change_me@example.com' then
    raise exception 'Put the person''s email address on the line marked CHANGE THIS first.';
  end if;

  select * into p from public.profiles where lower(email) = lower(btrim(target_email));
  if not found then
    raise exception 'No ZutLib account uses %. They need to sign up or be invited first.', target_email;
  end if;
  if not exists (select 1 from auth.users where id = p.id and email_confirmed_at is not null) then
    raise exception '% has not confirmed their email address yet.', target_email;
  end if;

  update public.profiles
     set role = 'super_admin', status = 'active', decided_at = now(), updated_at = now()
   where id = p.id;

  insert into public.audit_entries (actor_id, action, target_table, target_id, detail)
  values (null, 'system.restore_super_admin', 'profiles', p.id::text,
          jsonb_build_object('email', p.email, 'role_from', p.role, 'status_from', p.status,
                             'via', 'scripts/restore_super_admin.sql'));
end $$;

commit;

select full_name, email, role, status
  from public.profiles
 where role = 'super_admin'
 order by full_name;
