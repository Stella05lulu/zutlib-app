-- Copy reservation. Both are single statements, so the read and the write
-- of available_copies cannot be separated by another transaction.

create or replace function public.reserve_copy(p_resource uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare ok int;
begin
  update public.resources
     set available_copies = available_copies - 1
   where id = p_resource
     and is_physical = true
     and available_copies > 0;
  get diagnostics ok = row_count;
  return ok = 1;
end $$;

create or replace function public.release_copy(p_resource uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare ok int;
begin
  update public.resources
     set available_copies = available_copies + 1
   where id = p_resource
     and is_physical = true
     and available_copies < total_copies;
  get diagnostics ok = row_count;
  return ok = 1;
end $$;

revoke execute on function public.reserve_copy(uuid) from public, authenticated;
revoke execute on function public.release_copy(uuid) from public, authenticated;
