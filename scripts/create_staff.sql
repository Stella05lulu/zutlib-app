-- ZutLib — give staff accounts their role
--
-- Staff are not students, so they cannot pass the roll check in the
-- register function. Their accounts are created by the administrator in
-- the Supabase dashboard instead:
--
--   1. Authentication -> Users -> Add user -> Create new user
--        Email:     librarian@zutlib.test   (and again for admin@zutlib.test)
--        Password:  at least 8 characters
--        Tick "Auto Confirm User"  (no email is sent, none is needed)
--   2. Paste this file into SQL Editor and click Run.
--
-- Safe to run again: an existing profile only has its role updated.
-- Change the emails and names below if you used different ones.

insert into public.profiles (id, full_name, surname, role)
select u.id, s.full_name, s.surname, s.role::user_role
from (values
  ('librarian@zutlib.test', 'Library Desk',       'Desk',  'librarian'),
  ('admin@zutlib.test',     'System Administrator','Admin', 'admin')
) as s(email, full_name, surname, role)
join auth.users u on lower(u.email) = s.email
on conflict (id) do update set role = excluded.role;

-- Check: both rows should appear with the right role.
select p.full_name, u.email, p.role
from public.profiles p join auth.users u on u.id = p.id
where p.role in ('librarian', 'admin');
