-- ZutLib: new enum values for the super admin role and soft removal.
--
-- Postgres cannot use a new enum value in the same transaction that adds
-- it, so these live on their own. Run this file, then 0017.
--
--   super_admin  the top role. It can never come from sign-up or the app;
--                only scripts/restore_super_admin.sql can grant it.
--   removed      an account that was removed. Nothing is deleted, so a
--                super admin can restore it later.

alter type public.user_role add value if not exists 'super_admin';
alter type public.account_status add value if not exists 'removed';
