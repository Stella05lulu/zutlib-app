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

/// Which list the Study screen is showing: 0 notes, 1 flashcards, 2 quizzes.
final studyTabProvider = StateProvider<int>((_) => 0);

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
