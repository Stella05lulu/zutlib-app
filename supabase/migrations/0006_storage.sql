-- ZutLib — file storage for past papers, test papers and lecture notes.
-- Private bucket: files are only reachable through short-lived signed URLs
-- (see ResourceRepository.signedUrl). Staff upload; signed-in users read.

insert into storage.buckets (id, name, public)
values ('resources', 'resources', false)
on conflict (id) do nothing;

create policy resources_files_read on storage.objects
  for select to authenticated
  using (bucket_id = 'resources');

create policy resources_files_staff_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'resources' and public.is_staff());

create policy resources_files_staff_update on storage.objects
  for update to authenticated
  using (bucket_id = 'resources' and public.is_staff());

create policy resources_files_staff_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'resources' and public.is_staff());
