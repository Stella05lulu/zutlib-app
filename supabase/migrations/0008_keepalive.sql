-- ZutLib — keep the free project awake without a secret in GitHub
--
-- Free Supabase projects pause after seven days with no activity. The
-- GitHub workflow in .github/workflows/keepalive.yml calls this function
-- twice a week.
--
-- Before this migration the workflow wrote to the heartbeat table with the
-- SERVICE ROLE key, which meant storing the one key that bypasses all row
-- level security in GitHub. Now the workflow uses the public anon key and
-- can do exactly one thing: move the heartbeat timestamp. It cannot read or
-- write any other table, because anon holds no table privileges at all.

create or replace function public.beat()
returns timestamptz
language sql volatile security definer set search_path = public as $$
  update public.heartbeat set beat_at = now() where id = 1
  returning beat_at
$$;

revoke execute on function public.beat() from public;
grant usage on schema public to anon;
grant execute on function public.beat() to anon;
