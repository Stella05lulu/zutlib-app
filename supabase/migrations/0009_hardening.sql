-- ZutLib — security hardening before the defence
--
-- Each block closes one gap found in the September 2026 review
-- (DEFENCE_READINESS.md, section 2). Every one of them is proved by
-- supabase/tests/rls_negative.sql.
--
--   S1  borrowing requests carried whatever identity the client sent
--   S2  a file could be read by any signed-in account, even one with no
--       profile (an account made by calling sign-up directly)
--   S3  students could edit their own name, programme and department
--   S4  cancelling a request could also rewrite the rest of the row
--   S7  an administrator could demote themselves or the last administrator
--   F1  staff can now release a copy a student never collected
--       (handled in decide-request; nothing needed here)
--   N   students can mark their own notifications as read, nothing more

-- Repeated from 0007 in case that file was run before this line was
-- added to it: search needs pg_trgm's schema to be reachable.
grant usage on schema extensions to authenticated;

-- ================================================================ S1
-- The identity on a borrowing request is copied from the verified profile
-- by the database, whatever the client sent. The librarian's "Verified
-- requester" panel is therefore true by construction.
create or replace function public.stamp_borrow_identity()
returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = new.student_id;
  if not found then
    raise exception 'No profile for this account' using errcode = '42501';
  end if;
  new.student_name   := p.full_name;
  new.student_number := coalesce(p.student_number, '');
  new.programme      := p.programme;
  new.requested_at   := now();
  return new;
end $$;

drop trigger if exists borrow_stamp_identity on public.borrow_requests;
create trigger borrow_stamp_identity
  before insert on public.borrow_requests
  for each row execute function public.stamp_borrow_identity();

-- ================================================================ S4
-- Column level privileges. A policy decides WHICH rows; these decide WHICH
-- columns. A student may create a request with only these fields, and may
-- only ever change status and cancelled_at (the cancel policy then limits
-- that to "submitted -> cancelled" on their own row).
revoke insert, update on public.borrow_requests from authenticated;
grant insert (resource_id, student_id, student_name, student_number,
              programme, collection_date)
  on public.borrow_requests to authenticated;
grant update (status, cancelled_at) on public.borrow_requests to authenticated;

-- A cancellation records its own time.
create or replace function public.stamp_cancel_time()
returns trigger language plpgsql as $$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    new.cancelled_at := now();
  end if;
  return new;
end $$;

drop trigger if exists borrow_stamp_cancel on public.borrow_requests;
create trigger borrow_stamp_cancel
  before update on public.borrow_requests
  for each row execute function public.stamp_cancel_time();

-- ================================================================ S3
-- Profiles are written by the register function (service role) and by an
-- administrator changing a role. No client needs to change any other
-- column, so no client can.
revoke insert, update on public.profiles from authenticated;
grant update (role) on public.profiles to authenticated;

-- The old policy let a student rewrite their own name and programme.
-- Students now have no update policy at all; administrators keep theirs.
drop policy if exists profiles_update_own on public.profiles;

-- ================================================================ S7
-- An administrator cannot change their own role, and the last
-- administrator cannot be demoted by anyone. (auth.uid() is null in the
-- SQL editor, so the project owner can still repair roles there.)
create or replace function public.guard_admin_roles()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role then
    if auth.uid() is not null and new.id = auth.uid() then
      raise exception 'You cannot change your own role'
        using errcode = '42501';
    end if;
    if old.role = 'admin'
       and (select count(*) from public.profiles where role = 'admin') <= 1 then
      raise exception 'At least one administrator must remain'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard_admin on public.profiles;
create trigger profiles_guard_admin
  before update on public.profiles
  for each row execute function public.guard_admin_roles();

-- ================================================================ N
-- A student may only mark a notification read. Subject and body are
-- written by decide-request and cannot be edited.
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ================================================================ S2
-- Reading a file now needs the same thing as reading the catalogue:
-- a profile, which only the roll-checked register function creates.
drop policy if exists resources_files_read on storage.objects;
create policy resources_files_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'resources'
    and exists (select 1 from public.profiles where id = auth.uid())
  );
