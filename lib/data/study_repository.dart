import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/study.dart';
import '../study/practice.dart';
import 'offline_cache.dart';

/// The only place the study assistant talks to Supabase.
///
/// Nothing here filters by user: row level security in the database
/// returns only the signed-in student's own rows and refuses writes to
/// anyone else's. The app never sends a user_id; the database fills it in
/// from the signed request.
class StudyRepository {
  const StudyRepository();

  /// Database errors this module can cause, in words a student can act on.
  /// Anything else goes through the app-wide [Failure.from].
  static Failure _fail(Object e) {
    if (e is PostgrestException) {
      switch (e.code) {
        case '23503':
          return const Failure('That item no longer exists. Go back and refresh.');
        case '23514':
          return const Failure('That was not saved because it breaks a rule. '
              'Check that nothing is empty or too long and that no two options are the same.');
        case '54000':
          return Failure(e.message);
      }
    }
    return Failure.from(e);
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw _fail(e);
    }
  }

  static List<T> _rows<T>(Object? data, T Function(Map<String, dynamic>) make) => [
        for (final r in (data as List)) make(r as Map<String, dynamic>),
      ];

  // ------------------------------------------------------------- notes
  Future<List<Note>> notes() => _guard(() async {
        final data = await OfflineCache.rows('study.notes', () async {
          return await db.from('study_notes').select(Note.columns).order('updated_at', ascending: false);
        });
        return _rows(data, Note.fromMap);
      });

  Future<Note?> note(String id) => _guard(() async {
        final data = await OfflineCache.single('study.note.$id', () async {
          return await db.from('study_notes').select(Note.columns).eq('id', id).maybeSingle();
        });
        return data == null ? null : Note.fromMap(data);
      });

  Future<Note> createNote({
    required String title,
    required String body,
    String? courseCode,
    KitColor color = KitColor.blue,
  }) =>
      _guard(() async {
        final data = await db
            .from('study_notes')
            .insert({'title': title, 'body': body, 'course_code': courseCode, 'color': color.wire})
            .select(Note.columns)
            .single();
        return Note.fromMap(data);
      });

  Future<Note> updateNote(String id,
          {required String title, required String body, String? courseCode}) =>
      _guard(() async {
        final data = await db
            .from('study_notes')
            .update({'title': title, 'body': body, 'course_code': courseCode})
            .eq('id', id)
            .select(Note.columns)
            .single();
        return Note.fromMap(data);
      });

  /// Deletes a note, and its uploaded PDF if it has one.
  Future<void> deleteNote(Note note) => _guard(() async {
        await db.from('study_notes').delete().eq('id', note.id);
        final path = note.filePath;
        if (path != null) {
          try {
            await db.storage.from(_studyBucket).remove([path]);
          } catch (_) {
            // The note is gone; a leftover private file is harmless.
          }
        }
      });

  static const _studyBucket = 'study-files';

  /// Uploads a PDF to the student's own folder in the private study-files
  /// bucket, then makes a note built on it. Storage policies only allow a
  /// student to write inside the folder named after their account id.
  Future<Note> createPdfNote({
    required String title,
    required Uint8List bytes,
    required String fileName,
    String? courseCode,
    KitColor color = KitColor.blue,
  }) =>
      _guard(() async {
        final uid = currentUserId;
        if (uid == null) throw const Failure('Sign in again.');
        if (bytes.length > StudyLimits.pdfBytes) {
          throw const Failure('That PDF is larger than 10 MB. Choose a smaller file, for example one chapter.');
        }
        if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
          throw const Failure('That file is not a PDF.');
        }
        final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final base = safe.toLowerCase().endsWith('.pdf') ? safe.substring(0, safe.length - 4) : safe;
        final stem = base.length > 80 ? base.substring(0, 80) : base;
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$stem.pdf';
        await db.storage.from(_studyBucket).uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'application/pdf'),
            );
        try {
          final data = await db
              .from('study_notes')
              .insert({
                'title': title,
                'body': '',
                'course_code': courseCode,
                'file_path': path,
                'file_name': fileName.length > 200 ? fileName.substring(0, 200) : fileName,
                'color': color.wire,
              })
              .select(Note.columns)
              .single();
          return Note.fromMap(data);
        } catch (e) {
          try {
            await db.storage.from(_studyBucket).remove([path]);
          } catch (_) {
            // Leave it; the note was not made.
          }
          rethrow;
        }
      });

  /// Makes a note that studies a PDF already in the library.
  Future<Note> createLibraryNote({
    required String resourceId,
    required String title,
    String? courseCode,
    KitColor color = KitColor.blue,
  }) =>
      _guard(() async {
        final data = await db
            .from('study_notes')
            .insert({
              'title': title.length > StudyLimits.noteTitle ? title.substring(0, StudyLimits.noteTitle) : title,
              'body': '',
              'course_code': (courseCode ?? '').trim().isEmpty ? null : courseCode,
              'resource_id': resourceId,
              'color': color.wire,
            })
            .select(Note.columns)
            .single();
        return Note.fromMap(data);
      });

  /// Makes a kit built on a YouTube video. [youtubeUrl] must already be in
  /// the standard form (see normaliseYoutubeUrl).
  Future<Note> createVideoKit({required String title, required String youtubeUrl, KitColor color = KitColor.blue}) =>
      _guard(() async {
        final data = await db
            .from('study_notes')
            .insert({
              'title': title.length > StudyLimits.noteTitle ? title.substring(0, StudyLimits.noteTitle) : title,
              'body': '',
              'youtube_url': youtubeUrl,
              'color': color.wire,
            })
            .select(Note.columns)
            .single();
        return Note.fromMap(data);
      });

  Future<void> setKitColor(String noteId, KitColor color) => _guard(() async {
        await db.from('study_notes').update({'color': color.wire}).eq('id', noteId);
      });

  Future<void> renameKit(String noteId, String title) => _guard(() async {
        await db.from('study_notes').update({'title': title}).eq('id', noteId);
      });

  /// A short-lived link to open the PDF behind a note.
  Future<String> pdfUrl(Note note) => _guard(() async {
        if (note.filePath != null) {
          return await db.storage.from(_studyBucket).createSignedUrl(note.filePath!, 300);
        }
        if (note.resourceFilePath != null) {
          return await db.storage.from('resources').createSignedUrl(note.resourceFilePath!, 300);
        }
        throw const Failure('This note has no PDF.');
      });

  // ------------------------------------------------------------- summaries
  Future<List<Summary>> summaries(String noteId) => _guard(() async {
        final data = await db
            .from('study_summaries')
            .select(Summary.columns)
            .eq('note_id', noteId)
            .order('created_at', ascending: false);
        return _rows(data, Summary.fromMap);
      });

  Future<void> addSummary(String noteId, String body) => _guard(() async {
        await db.from('study_summaries').insert({'note_id': noteId, 'body': body});
      });

  Future<void> updateSummary(String id, String body) =>
      _guard(() async {
        await db.from('study_summaries').update({'body': body}).eq('id', id);
      });

  Future<void> deleteSummary(String id) =>
      _guard(() async {
        await db.from('study_summaries').delete().eq('id', id);
      });

  // ------------------------------------------------------------- decks
  Future<List<Deck>> decks({String? noteId}) => _guard(() async {
        var query = db.from('study_decks').select(Deck.columns);
        if (noteId != null) query = query.eq('note_id', noteId);
        final data = await OfflineCache.rows('study.decks.${noteId ?? 'all'}', () async {
          return await query.order('updated_at', ascending: false);
        });
        return _rows(data, Deck.fromMap);
      });

  Future<Deck?> deck(String id) => _guard(() async {
        final data = await db.from('study_decks').select(Deck.columns).eq('id', id).maybeSingle();
        return data == null ? null : Deck.fromMap(data);
      });

  Future<Deck> createDeck(String title, {String? noteId}) => _guard(() async {
        final data = await db
            .from('study_decks')
            .insert({'title': title, 'note_id': noteId})
            .select(Deck.columns)
            .single();
        return Deck.fromMap(data);
      });

  Future<void> renameDeck(String id, String title) =>
      _guard(() async {
        await db.from('study_decks').update({'title': title}).eq('id', id);
      });

  Future<void> deleteDeck(String id) =>
      _guard(() async {
        await db.from('study_decks').delete().eq('id', id);
      });

  Future<List<Flashcard>> cards(String deckId) => _guard(() async {
        final data = await OfflineCache.rows('study.cards.$deckId', () async {
          return await db
              .from('study_flashcards')
              .select(Flashcard.columns)
              .eq('deck_id', deckId)
              .order('position', ascending: true)
              .order('created_at', ascending: true);
        });
        return _rows(data, Flashcard.fromMap);
      });

  Future<void> addCard(String deckId, {required String front, required String back, required int position}) =>
      _guard(() async {
        await db
          .from('study_flashcards')
          .insert({'deck_id': deckId, 'front': front, 'back': back, 'position': position});
      });

  Future<void> updateCard(String id, {required String front, required String back}) => _guard(() async {
        await db.from('study_flashcards').update({'front': front, 'back': back}).eq('id', id);
      });

  Future<void> deleteCard(String id) =>
      _guard(() async {
        await db.from('study_flashcards').delete().eq('id', id);
      });

  // ------------------------------------------------------------- quizzes
  Future<List<Quiz>> quizzes({String? noteId}) => _guard(() async {
        var query = db.from('study_quizzes').select(Quiz.columns);
        if (noteId != null) query = query.eq('note_id', noteId);
        final data = await OfflineCache.rows('study.quizzes.${noteId ?? 'all'}', () async {
          return await query.order('updated_at', ascending: false);
        });
        return _rows(data, Quiz.fromMap);
      });

  Future<Quiz?> quiz(String id) => _guard(() async {
        final data = await db.from('study_quizzes').select(Quiz.columns).eq('id', id).maybeSingle();
        return data == null ? null : Quiz.fromMap(data);
      });

  Future<Quiz> createQuiz(String title, {String? noteId}) => _guard(() async {
        final data = await db
            .from('study_quizzes')
            .insert({'title': title, 'note_id': noteId})
            .select(Quiz.columns)
            .single();
        return Quiz.fromMap(data);
      });

  Future<void> renameQuiz(String id, String title) =>
      _guard(() async {
        await db.from('study_quizzes').update({'title': title}).eq('id', id);
      });

  Future<void> deleteQuiz(String id) =>
      _guard(() async {
        await db.from('study_quizzes').delete().eq('id', id);
      });

  Future<List<QuizQuestion>> questions(String quizId) => _guard(() async {
        final data = await OfflineCache.rows('study.questions.$quizId', () async {
          return await db
              .from('study_quiz_questions')
              .select(QuizQuestion.columns)
              .eq('quiz_id', quizId)
              .order('position', ascending: true)
              .order('created_at', ascending: true);
        });
        return _rows(data, QuizQuestion.fromMap);
      });

  Future<void> addQuestion(
    String quizId, {
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? explanation,
    required int position,
    int difficulty = 2,
  }) =>
      _guard(() async {
        await db.from('study_quiz_questions').insert({
            'quiz_id': quizId,
            'prompt': prompt,
            'options': options,
            'correct_index': correctIndex,
            'explanation': explanation,
            'position': position,
            'difficulty': difficulty,
          });
      });

  Future<void> updateQuestion(
    String id, {
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? explanation,
  }) =>
      _guard(() async {
        await db.from('study_quiz_questions').update({
            'prompt': prompt,
            'options': options,
            'correct_index': correctIndex,
            'explanation': explanation,
          }).eq('id', id);
      });

  Future<void> deleteQuestion(String id) =>
      _guard(() async {
        await db.from('study_quiz_questions').delete().eq('id', id);
      });

  /// Saves an attempt. The database checks the answers and works out the
  /// score itself; what comes back is its verdict.
  Future<QuizAttempt> submitAttempt(String quizId, Map<String, int> answers) => _guard(() async {
        final data = await db
            .from('study_quiz_attempts')
            .insert({'quiz_id': quizId, 'answers': answers})
            .select(QuizAttempt.columns)
            .single();
        return QuizAttempt.fromMap(data);
      });

  // ------------------------------------------------------------- kits
  Future<StudyGuide?> guide(String noteId) => _guard(() async {
        final data = await OfflineCache.single('study.guide.$noteId', () async {
          return await db.from('study_guides').select(StudyGuide.columns).eq('note_id', noteId).maybeSingle();
        });
        return data == null ? null : StudyGuide.fromMap(data);
      });

  /// Every guide the student has, for the kit list.
  Future<List<StudyGuide>> guides() => _guard(() async {
        final data = await OfflineCache.rows('study.guides', () async {
          return await db.from('study_guides').select(StudyGuide.columns);
        });
        return _rows(data, StudyGuide.fromMap);
      });

  /// Card id to box (0 Learning to 3 Mastered) for the given cards.
  Future<Map<String, int>> cardBoxes(List<String> cardIds) => _guard(() async {
        if (cardIds.isEmpty) return <String, int>{};
        final data = await OfflineCache.rows('study.boxes.${cardIds.first}', () async {
          return await db.from('study_card_progress').select('card_id,box').inFilter('card_id', cardIds);
        });
        return {
          for (final r in (data as List)) (r as Map)['card_id'] as String: ((r['box'] as num?) ?? 0).toInt(),
        };
      });

  Future<void> rateCard(String cardId, CardBox box) => _guard(() async {
        await db.rpc('study_rate_card', params: {'p_card': cardId, 'p_box': box.index});
      });

  /// Question id to stars (0 to 3) for the given questions.
  Future<Map<String, int>> questionStars(List<String> questionIds) => _guard(() async {
        if (questionIds.isEmpty) return <String, int>{};
        final data = await OfflineCache.rows('study.stars.${questionIds.first}', () async {
          return await db
              .from('study_question_progress')
              .select('question_id,stars')
              .inFilter('question_id', questionIds);
        });
        return {
          for (final r in (data as List)) (r as Map)['question_id'] as String: ((r['stars'] as num?) ?? 0).toInt(),
        };
      });

  Future<void> rateQuestion(String questionId, int stars) => _guard(() async {
        await db.rpc('study_rate_question', params: {'p_question': questionId, 'p_stars': stars});
      });

  /// Starts Smart Study again: every star for these questions is removed.
  Future<void> resetStars(List<String> questionIds) => _guard(() async {
        if (questionIds.isEmpty) return;
        await db.from('study_question_progress').delete().inFilter('question_id', questionIds);
      });

  /// Starts the deck again: every card goes back to Learning.
  Future<void> resetBoxes(List<String> cardIds) => _guard(() async {
        if (cardIds.isEmpty) return;
        await db.from('study_card_progress').delete().inFilter('card_id', cardIds);
      });

  // ------------------------------------------------------------- tests
  Future<List<StudyTest>> tests(String noteId) => _guard(() async {
        final data = await db
            .from('study_tests')
            .select(StudyTest.columns)
            .eq('note_id', noteId)
            .order('created_at', ascending: false);
        return _rows(data, StudyTest.fromMap);
      });

  Future<StudyTest?> test(String id) => _guard(() async {
        final data = await db.from('study_tests').select(StudyTest.columns).eq('id', id).maybeSingle();
        return data == null ? null : StudyTest.fromMap(data);
      });

  /// The database checks every question belongs to [quizId] and appears
  /// once.
  Future<StudyTest> createTest({
    required String noteId,
    required String quizId,
    required String title,
    required List<String> questionIds,
    required String difficulty,
    required int timeLimitSeconds,
  }) =>
      _guard(() async {
        final data = await db
            .from('study_tests')
            .insert({
              'note_id': noteId,
              'quiz_id': quizId,
              'title': title,
              'question_ids': questionIds,
              'difficulty': difficulty,
              'time_limit_s': timeLimitSeconds,
            })
            .select(StudyTest.columns)
            .single();
        return StudyTest.fromMap(data);
      });

  Future<void> deleteTest(String id) => _guard(() async {
        await db.from('study_tests').delete().eq('id', id);
      });

  /// Saves a finished test. The database marks it; what comes back is its
  /// verdict.
  Future<TestAttempt> submitTest(String testId, Map<String, int> answers, int secondsTaken) => _guard(() async {
        final data = await db
            .from('study_test_attempts')
            .insert({'test_id': testId, 'answers': answers, 'seconds_taken': secondsTaken.clamp(0, 86400)})
            .select(TestAttempt.columns)
            .single();
        return TestAttempt.fromMap(data);
      });

  // ------------------------------------------------------------- games
  Future<void> saveGameScore(String deckId, GameKind game, int score, int seconds) => _guard(() async {
        await db.from('study_game_scores').insert({
          'deck_id': deckId,
          'game': game.wire,
          'score': score.clamp(0, 10000),
          'seconds': seconds.clamp(0, 36000),
        });
      });

  /// The best ten scores for one game on one deck.
  Future<List<GameScore>> gameScores(String deckId, GameKind game) => _guard(() async {
        final data = await db
            .from('study_game_scores')
            .select(GameScore.columns)
            .eq('deck_id', deckId)
            .eq('game', game.wire)
            .order('score', ascending: false)
            .limit(10);
        return _rows(data, GameScore.fromMap);
      });

  // ------------------------------------------------------------- AI
  Future<AiStatus> aiStatus() => _guard(() async {
        final data = await db.rpc('study_ai_status');
        final rows = data as List;
        if (rows.isEmpty) return const AiStatus(used: 0, dailyLimit: 0, remaining: 0);
        return AiStatus.fromMap(rows.first as Map<String, dynamic>);
      });

  /// Asks the study-generate Edge Function to make a summary, deck or quiz
  /// from a note. The Gemini key lives only inside that function.
  Future<GenerateResult> generate(StudyKind kind, String noteId) => _guard(() async {
        final res = await db.functions.invoke(
          'study-generate',
          body: {'type': kind.wire, 'note_id': noteId},
        );
        final result = GenerateResult.tryParse(res.data);
        if (result == null) {
          throw const Failure('The server sent an answer the app did not understand. Try again.');
        }
        return result;
      });
}
