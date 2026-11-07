-- ZutLib: a complete study kit and exam plan for Sample Student A, for the
-- LOCAL Supabase only. Without a Gemini key no kit gets an AI guide, so this
-- writes one by hand. scripts/local_setup.sh runs it after the other seeds.
-- Safe to run again: it replaces what an earlier run made, and the exam stays
-- ten days away.

do $$
declare
  owner uuid := (select id from auth.users where lower(email) = 'sample.student.a@zutlib.test');
  kit   uuid := (select id from public.study_notes
                  where user_id = owner and title = 'Sample: Ohm''s law and resistors');
  deck  uuid := (select id from public.study_decks where note_id = kit limit 1);
  quiz  uuid;
begin
  if kit is null or deck is null then
    raise exception 'Run scripts/seed_study_demo.sql first: the Ohm''s law kit is missing.';
  end if;

  delete from public.study_plans where note_id = kit;
  delete from public.study_guides where note_id = kit;
  delete from public.study_quizzes where note_id = kit;
  delete from public.study_flashcards where deck_id = deck and position >= 100;

  insert into public.study_flashcards (user_id, deck_id, front, back, position) values
    (owner, deck, 'What is the unit of power?', 'The watt (W).', 100),
    (owner, deck, 'Give the power formula using V and I.', 'P = V x I.', 101),
    (owner, deck, 'How do series resistors combine?', 'They add: R = R1 + R2.', 102),
    (owner, deck, 'What stays the same across parallel branches?', 'The voltage.', 103),
    (owner, deck, 'What does the third colour band on a resistor show?', 'The multiplier.', 104),
    (owner, deck, 'What does the tolerance band show?', 'How far the real value may differ.', 105);

  insert into public.study_quizzes (user_id, note_id, title, source)
  values (owner, kit, 'Sample: Ohm''s law practice', 'manual')
  returning id into quiz;

  insert into public.study_quiz_questions (user_id, quiz_id, prompt, options, correct_index, explanation, position) values
    (owner, quiz, 'A 12 V supply drives 2 A. What is the resistance?', array['3 ohms','6 ohms','10 ohms','24 ohms'], 1, 'R = V / I = 12 / 2.', 0),
    (owner, quiz, 'Which formula is Ohm''s law?', array['V = I x R','P = I / V','R = V x I','I = V x R'], 0, 'Voltage equals current times resistance.', 1),
    (owner, quiz, 'What is 100 ohms in series with 220 ohms?', array['68 ohms','120 ohms','320 ohms','22000 ohms'], 2, 'Series resistors add.', 2),
    (owner, quiz, 'What is the same through series resistors?', array['Voltage','Current','Power','Heat'], 1, 'One path means one current.', 3),
    (owner, quiz, 'Two 100 ohm resistors in parallel give what?', array['25 ohms','50 ohms','100 ohms','200 ohms'], 1, 'Equal parallel resistors halve.', 4),
    (owner, quiz, '5 V across 1 kilohm draws what current?', array['0.5 mA','5 mA','50 mA','5 A'], 1, 'I = 5 / 1000 = 5 mA.', 5),
    (owner, quiz, 'What power does 10 V at 2 A use?', array['5 W','8 W','12 W','20 W'], 3, 'P = V x I.', 6),
    (owner, quiz, 'What does the first band of a resistor show?', array['First digit','Multiplier','Tolerance','Power rating'], 0, 'Bands one and two are digits.', 7);

  insert into public.study_guides (user_id, note_id, deck_id, quiz_id, overview, sections) values (
    owner, kit, deck, quiz,
    'How voltage, current and resistance relate, and how to work with resistors in a circuit.',
    jsonb_build_array(
      jsonb_build_object('heading', 'Voltage, current and resistance',
        'summary', 'Voltage pushes charge, current is the flow of charge, and resistance opposes that flow.',
        'points', jsonb_build_array('Voltage is measured in volts', 'Current is measured in amps', 'Resistance is measured in ohms')),
      jsonb_build_object('heading', 'Ohm''s law',
        'summary', 'Voltage equals current times resistance, so knowing two values gives the third.',
        'points', jsonb_build_array('V = I x R', 'I = V / R', 'R = V / I')),
      jsonb_build_object('heading', 'Series and parallel',
        'summary', 'Series resistors add up. Parallel resistors give a smaller total than any one branch.',
        'points', jsonb_build_array('Series: one current', 'Parallel: one voltage')),
      jsonb_build_object('heading', 'Power',
        'summary', 'Power is the rate energy is used, and a resistor turns it into heat.',
        'points', jsonb_build_array('P = V x I', 'Measured in watts')),
      jsonb_build_object('heading', 'Reading resistor colours',
        'summary', 'The colour bands give two digits, a multiplier and a tolerance.',
        'points', jsonb_build_array('Bands one and two are digits', 'Band three is the multiplier', 'The last band is the tolerance'))
    ));

  insert into public.study_plans (user_id, note_id, exam_date, study_days, minutes, start_date)
  values (owner, kit, current_date + 10, 127, 30, current_date);
end $$;
