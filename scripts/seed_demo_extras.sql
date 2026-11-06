-- ZutLib: SAMPLE DATA for the screens added by the build plan
--
-- Fills Home, Saved, My progress, multi-source kits, Announcements,
-- librarian Today, the admin Overview and the audit log, so no screen is
-- empty in front of the judges. Everything it makes is labelled "Sample"
-- and goes through the same tables (and, for administrator actions, the
-- same audited functions) the app uses.
--
-- RUN AFTER
--   1. migrations 0001 to 0021
--   2. python scripts/sample_data.py seed      (the sample books and papers)
--   3. scripts/seed_study_demo.sql              (Sample Student A and B)
--   4. scripts/restore_super_admin.sql          (so an administrator exists)
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query -> paste this file -> Run.
-- Safe to run again: it first removes what an earlier run made for the
-- two sample students and the sample announcements. Real accounts and real
-- borrowing are never touched.

do $$
declare
  a      uuid := (select id from auth.users where lower(email) = 'sample.student.a@zutlib.test');
  b      uuid := (select id from auth.users where lower(email) = 'sample.student.b@zutlib.test');
  boss   uuid := (select id from public.profiles where role in ('super_admin', 'admin') and status = 'active'
                   order by (role = 'super_admin') desc, created_at limit 1);
  kit    uuid;
  quiz   uuid;
  qs     uuid[];
  paper  uuid;
  books  uuid[];
  r      uuid;
  req    uuid;
  wk     int;
  ann    uuid;
begin
  if a is null or b is null then
    raise exception 'Run scripts/seed_study_demo.sql first: Sample Student A and B are missing.';
  end if;
  if boss is null then
    raise exception 'No active administrator. Run scripts/restore_super_admin.sql first.';
  end if;
  select array_agg(id order by title) into books from (
    select id, title from public.resources
     where is_sample and type = 'book' and is_physical and retired_at is null and total_copies >= 2
     order by title limit 4) x;
  select id into paper from public.resources
   where is_sample and type = 'past_paper' and retired_at is null and file_path ilike '%.pdf'
   order by academic_year desc, title limit 1;
  if coalesce(array_length(books, 1), 0) < 4 or paper is null then
    raise exception 'Run python scripts/sample_data.py seed first: sample books and papers are missing.';
  end if;

  -- ------------------------------------------------------------ reset
  perform set_config('zutlib.break_glass', 'off', true);
  delete from public.saved_resources where user_id in (a, b);
  delete from public.study_note_sources where user_id in (a, b);
  delete from public.study_quiz_attempts where user_id in (a, b);
  -- Copies held by earlier sample loans go back on the shelf first.
  update public.resources r2 set available_copies = available_copies + x.n
    from (select resource_id, count(*) n from public.borrow_requests
           where student_id in (a, b) and status in ('approved', 'collected') group by 1) x
   where r2.id = x.resource_id;
  delete from public.borrow_requests where student_id in (a, b);
  update public.announcements set removed_at = coalesce(removed_at, now()) where is_sample;

  -- ------------------------------------------------------------ announcements
  -- Posted through the audited function, as the administrator, so the
  -- audit log shows real entries for them.
  perform set_config('request.jwt.claims', json_build_object('sub', boss, 'role', 'authenticated')::text, true);
  ann := (public.admin_save_announcement(null, 'Sample: Extended library hours',
     'Sample announcement. During the examination period the library stays open until 20:00, Monday to Friday.')).id;
  update public.announcements set is_sample = true where id = ann;
  ann := (public.admin_save_announcement(null, 'Sample: New ICT past papers',
     'Sample announcement. Past papers for ICT 2010 and ICT 3020 have been added to Explore.', 'ICT',
     public.zl_today() + 30)).id;
  update public.announcements set is_sample = true where id = ann;
  ann := (public.admin_save_announcement(null, 'Sample: Engineering lab manuals',
     'Sample announcement. Lab manuals for second year Engineering can be borrowed from the front desk.',
     'Engineering')).id;
  update public.announcements set is_sample = true where id = ann;
  perform set_config('request.jwt.claims', '', true);

  -- ------------------------------------------------------------ saved
  insert into public.saved_resources (user_id, resource_id, created_at)
  select a, x, now() - (i || ' days')::interval
    from unnest(books[1:3] || array[paper]) with ordinality as t(x, i);

  -- ------------------------------------------------------------ a kit with several sources
  select id into kit from public.study_notes where user_id = a and title like 'Sample: Ohm%' limit 1;
  if kit is not null then
    insert into public.study_note_sources (user_id, note_id, kind, label, body)
    values (a, kit, 'text', 'Sample: formula sheet',
            'V = I R. Series: R = R1 + R2. Parallel: 1/R = 1/R1 + 1/R2. Power: P = V I = I squared R.');
    insert into public.study_note_sources (user_id, note_id, kind, label, resource_id)
    values (a, kit, 'library', 'Sample past paper', paper);
  end if;

  -- ------------------------------------------------------------ quiz attempts over six weeks
  -- Scored by the database trigger, like any attempt from the app; only
  -- the dates are moved back afterwards, to draw the progress chart.
  select id into quiz from public.study_quizzes where user_id = a order by created_at limit 1;
  if quiz is not null then
    select array_agg(id order by position) into qs from public.study_quiz_questions where quiz_id = quiz;
    for wk in reverse 5..0 loop
      insert into public.study_quiz_attempts (user_id, quiz_id, answers)
      select a, quiz, jsonb_object_agg(q.id::text, case
               -- Early weeks: some wrong answers; later weeks: all right.
               when wk >= 4 and q.position = (select max(position) from public.study_quiz_questions where quiz_id = quiz)
                 then (q.correct_index + 1) % greatest(cardinality(q.options), 2)
               when wk >= 2 and q.id = qs[1] and wk % 2 = 0
                 then (q.correct_index + 1) % greatest(cardinality(q.options), 2)
               else q.correct_index end)
        from public.study_quiz_questions q where q.quiz_id = quiz
      returning id into r;
      update public.study_quiz_attempts
         set created_at = now() - make_interval(days => wk * 7 + 1)
       where id = r;
    end loop;
  end if;

  -- ------------------------------------------------------------ borrowing
  -- One overdue loan and one on time for A, and one request waiting for a
  -- librarian from B. Copies are reserved the same way decide-request does.
  insert into public.borrow_requests (resource_id, student_id, student_name, student_number, collection_date)
  values (books[1], a, '', '', public.zl_today() - 20) returning id into req;
  perform public.reserve_copy(books[1]);
  update public.borrow_requests set status = 'approved', decided_by = boss, decided_at = now() - interval '20 days' where id = req;
  update public.borrow_requests set status = 'collected', collected_at = now() - interval '19 days',
         due_date = public.zl_today() - 5 where id = req;

  insert into public.borrow_requests (resource_id, student_id, student_name, student_number, collection_date)
  values (books[2], a, '', '', public.zl_today() - 2) returning id into req;
  perform public.reserve_copy(books[2]);
  update public.borrow_requests set status = 'approved', decided_by = boss, decided_at = now() - interval '2 days' where id = req;
  update public.borrow_requests set status = 'collected', collected_at = now() - interval '1 day',
         due_date = public.zl_today() - 1 + (select loan_days from public.settings limit 1) where id = req;

  insert into public.borrow_requests (resource_id, student_id, student_name, student_number, collection_date)
  values (books[3], b, '', '', public.zl_today());
end $$;

-- ---------------------------------------------------------------- check
select 'announcements' as what, count(*)::text as how_many from public.announcements where is_sample and removed_at is null
union all select 'saved (Student A)', count(*)::text from public.saved_resources s join auth.users u on u.id = s.user_id
  where lower(u.email) = 'sample.student.a@zutlib.test'
union all select 'extra kit sources', count(*)::text from public.study_note_sources s join auth.users u on u.id = s.user_id
  where lower(u.email) = 'sample.student.a@zutlib.test'
union all select 'quiz attempts', count(*)::text from public.study_quiz_attempts s join auth.users u on u.id = s.user_id
  where lower(u.email) = 'sample.student.a@zutlib.test'
union all select 'overdue loans', count(*)::text from public.borrow_requests b join auth.users u on u.id = b.student_id
  where lower(u.email) like 'sample.student._@zutlib.test' and b.status = 'collected' and b.due_date < public.zl_today();
