-- Minimal stand-in for the parts of a Supabase database that the ZutLib
-- migrations rely on, so they can be run and tested on a plain Postgres.
-- It is NOT applied to the real project: Supabase already provides all of it.
-- Roles belong to the whole server, so create them only once.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
    create role authenticated nologin noinherit;
    create role service_role nologin noinherit bypassrls;
    create role authenticator login noinherit password 'authenticator';
    grant anon, authenticated, service_role to authenticator;
  end if;
end $$;

create schema auth;
create schema extensions;
create schema storage;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (
  id uuid primary key,
  email text,
  email_confirmed_at timestamptz default now(),
  raw_user_meta_data jsonb default '{}'::jsonb,
  raw_app_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

-- Same definition Supabase uses: the "sub" claim of the request's JWT.
create function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(
    current_setting('request.jwt.claim.sub', true),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ), '')::uuid
$$;
create function auth.role() returns text language sql stable as $$
  select coalesce(
    current_setting('request.jwt.claim.role', true),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )
$$;
grant execute on function auth.uid(), auth.role() to anon, authenticated, service_role;

create table storage.buckets (id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(),
  bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated, service_role;
grant select, insert, delete on storage.objects to authenticated;
grant all on storage.objects, storage.buckets to service_role;

-- Same as Supabase's helper: the folder names in an object path.
-- Supabase blocks direct DELETE on storage tables unless the Storage API
-- sets storage.allow_delete_query (storage migration 0055). Same here.
create function storage.protect_delete() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('storage.allow_delete_query', true), 'false') != 'true' then
    raise exception 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
      using errcode = '42501';
  end if;
  return null;
end $$;
create trigger protect_objects_delete before delete on storage.objects
  for each statement execute function storage.protect_delete();
create trigger protect_buckets_delete before delete on storage.buckets
  for each statement execute function storage.protect_delete();

create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant execute on function storage.foldername(text) to authenticated, service_role;

-- Worst case for privileges: behave like a Supabase project whose default
-- privileges expose every new table and function to every API role. The
-- study migration must still lock itself down explicitly.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

-- Added for 0018: invited users have invited_at set, and sign-in sessions.
alter table auth.users add column if not exists invited_at timestamptz;
create table if not exists auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);
-- Added for 0020: Storage keeps each file's size in metadata.
alter table storage.objects add column if not exists metadata jsonb;
