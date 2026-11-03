import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/study_repository.dart';
import '../models/study.dart';
import 'providers.dart';

/// Riverpod providers for the study assistant. Each one watches
/// [userIdProvider], so signing out and back in as someone else never
/// shows the previous student's notes from memory.

const studyRepo = StudyRepository();

final notesProvider = FutureProvider<List<Note>>((ref) {
  ref.watch(userIdProvider);
  return studyRepo.notes();
});

final noteProvider = FutureProvider.autoDispose.family<Note?, String>((ref, id) {
  ref.watch(userIdProvider);
  return studyRepo.note(id);
});

final summariesProvider = FutureProvider.autoDispose.family<List<Summary>, String>((ref, noteId) {
  ref.watch(userIdProvider);
  return studyRepo.summaries(noteId);
});

final decksProvider = FutureProvider<List<Deck>>((ref) {
  ref.watch(userIdProvider);
  return studyRepo.decks();
});

final noteDecksProvider = FutureProvider.autoDispose.family<List<Deck>, String>((ref, noteId) {
  ref.watch(userIdProvider);
  return studyRepo.decks(noteId: noteId);
});

final deckProvider = FutureProvider.autoDispose.family<Deck?, String>((ref, id) {
  ref.watch(userIdProvider);
  return studyRepo.deck(id);
});

final cardsProvider = FutureProvider.autoDispose.family<List<Flashcard>, String>((ref, deckId) {
  ref.watch(userIdProvider);
  return studyRepo.cards(deckId);
});

final quizzesProvider = FutureProvider<List<Quiz>>((ref) {
  ref.watch(userIdProvider);
  return studyRepo.quizzes();
});

final noteQuizzesProvider = FutureProvider.autoDispose.family<List<Quiz>, String>((ref, noteId) {
  ref.watch(userIdProvider);
  return studyRepo.quizzes(noteId: noteId);
});

final quizProvider = FutureProvider.autoDispose.family<Quiz?, String>((ref, id) {
  ref.watch(userIdProvider);
  return studyRepo.quiz(id);
});

final questionsProvider = FutureProvider.autoDispose.family<List<QuizQuestion>, String>((ref, quizId) {
  ref.watch(userIdProvider);
  return studyRepo.questions(quizId);
});

final aiStatusProvider = FutureProvider.autoDispose<AiStatus>((ref) {
  ref.watch(userIdProvider);
  return studyRepo.aiStatus();
});

/// After any change, refresh every list that could show it.
void refreshStudy(WidgetRef ref, {String? noteId, String? deckId, String? quizId}) {
  ref.invalidate(notesProvider);
  ref.invalidate(decksProvider);
  ref.invalidate(quizzesProvider);
  if (noteId != null) {
    ref.invalidate(noteProvider(noteId));
    ref.invalidate(summariesProvider(noteId));
    ref.invalidate(noteDecksProvider(noteId));
    ref.invalidate(noteQuizzesProvider(noteId));
  }
  if (deckId != null) {
    ref.invalidate(deckProvider(deckId));
    ref.invalidate(cardsProvider(deckId));
  }
  if (quizId != null) {
    ref.invalidate(quizProvider(quizId));
    ref.invalidate(questionsProvider(quizId));
  }
}

// ------------------------------------------------------------------ kits

/// Everything one study kit's screens need, loaded together.
class KitData {
  const KitData({
    required this.note,
    required this.guide,
    required this.deck,
    required this.cards,
    required this.quiz,
    required this.questions,
    required this.boxes,
    required this.stars,
  });

  final Note note;
  final StudyGuide? guide;

  /// The kit's flashcard deck: the one its AI guide made, or else the
  /// newest deck made for this kit.
  final Deck? deck;
  final List<Flashcard> cards;

  /// The kit's question bank, chosen the same way.
  final Quiz? quiz;
  final List<QuizQuestion> questions;

  /// Card id to box, question id to stars.
  final Map<String, int> boxes;
  final Map<String, int> stars;
}

T? _pick<T>(List<T> items, String? preferredId, String Function(T) idOf) {
  if (items.isEmpty) return null;
  if (preferredId != null) {
    for (final i in items) {
      if (idOf(i) == preferredId) return i;
    }
  }
  return items.first;
}

final kitProvider = FutureProvider.autoDispose.family<KitData?, String>((ref, noteId) async {
  ref.watch(userIdProvider);
  final note = await studyRepo.note(noteId);
  if (note == null) return null;
  final loaded = await Future.wait<Object?>([
    studyRepo.guide(noteId),
    studyRepo.decks(noteId: noteId),
    studyRepo.quizzes(noteId: noteId),
  ]);
  final guide = loaded[0] as StudyGuide?;
  final deck = _pick(loaded[1] as List<Deck>, guide?.deckId, (d) => d.id);
  final quiz = _pick(loaded[2] as List<Quiz>, guide?.quizId, (q) => q.id);
  final content = await Future.wait<Object?>([
    deck == null ? Future.value(const <Flashcard>[]) : studyRepo.cards(deck.id),
    quiz == null ? Future.value(const <QuizQuestion>[]) : studyRepo.questions(quiz.id),
  ]);
  final cards = content[0] as List<Flashcard>;
  final questions = content[1] as List<QuizQuestion>;
  final progress = await Future.wait<Map<String, int>>([
    studyRepo.cardBoxes([for (final c in cards) c.id]),
    studyRepo.questionStars([for (final q in questions) q.id]),
  ]);
  return KitData(
    note: note,
    guide: guide,
    deck: deck,
    cards: cards,
    quiz: quiz,
    questions: questions,
    boxes: progress[0],
    stars: progress[1],
  );
});

/// One row of the kit list: the kit and how much is in it.
class KitSummary {
  const KitSummary({required this.note, required this.cardCount, required this.questionCount, required this.hasGuide});
  final Note note;
  final int cardCount;
  final int questionCount;
  final bool hasGuide;
}

final kitListProvider = FutureProvider.autoDispose<List<KitSummary>>((ref) async {
  ref.watch(userIdProvider);
  final loaded = await Future.wait<Object?>([
    ref.watch(notesProvider.future),
    ref.watch(decksProvider.future),
    ref.watch(quizzesProvider.future),
    studyRepo.guides(),
  ]);
  final notes = loaded[0] as List<Note>;
  final decks = loaded[1] as List<Deck>;
  final quizzes = loaded[2] as List<Quiz>;
  final guides = loaded[3] as List<StudyGuide>;
  return [
    for (final n in notes)
      KitSummary(
        note: n,
        cardCount: decks.where((d) => d.noteId == n.id).fold(0, (sum, d) => sum + d.cardCount),
        questionCount: quizzes.where((q) => q.noteId == n.id).fold(0, (sum, q) => sum + q.questionCount),
        hasGuide: guides.any((g) => g.noteId == n.id),
      ),
  ];
});

final testsProvider = FutureProvider.autoDispose.family<List<StudyTest>, String>((ref, noteId) {
  ref.watch(userIdProvider);
  return studyRepo.tests(noteId);
});

final testProvider = FutureProvider.autoDispose.family<StudyTest?, String>((ref, id) {
  ref.watch(userIdProvider);
  return studyRepo.test(id);
});

final gameScoresProvider =
    FutureProvider.autoDispose.family<List<GameScore>, ({String deckId, GameKind game})>((ref, key) {
  ref.watch(userIdProvider);
  return studyRepo.gameScores(key.deckId, key.game);
});

/// After any change to a kit, refresh everything that could show it.
void refreshKit(WidgetRef ref, String noteId) {
  ref.invalidate(kitProvider(noteId));
  ref.invalidate(testsProvider(noteId));
  ref.invalidate(kitListProvider);
  ref.invalidate(aiStatusProvider);
  refreshStudy(ref, noteId: noteId);
}
