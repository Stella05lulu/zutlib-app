/// The study assistant's data, as the app sees it. Each class mirrors one
/// table in supabase/migrations/0010_study_assistant.sql.
library;

DateTime _time(Object? v) => DateTime.parse(v as String).toLocal();

/// Where a summary, deck or quiz came from.
enum StudySource { manual, ai }

StudySource _source(Object? v) => v == 'ai' ? StudySource.ai : StudySource.manual;

/// The three things AI can make from a note. [wire] is the value the
/// study-generate function expects in "type".
enum StudyKind { summary, flashcards, quiz }

extension StudyKindX on StudyKind {
  String get wire => name;

  static StudyKind? parse(Object? v) => switch (v) {
        'summary' => StudyKind.summary,
        'flashcards' => StudyKind.flashcards,
        'quiz' => StudyKind.quiz,
        _ => null,
      };
}

/// The length rules on what a student types. They mirror the CHECK
/// constraints in 0010_study_assistant.sql so a form can say "too long"
/// before sending; the database is still the authority and refuses
/// anything that breaks them.
abstract final class StudyLimits {
  static const noteTitle = 200;
  static const noteBody = 20000;

  /// The study-files bucket's size limit (0013_study_pdfs.sql), so the app
  /// can say "too big" before uploading.
  static const pdfBytes = 10 * 1024 * 1024;
  static const courseCode = 20;
  static const summary = 5000;
  static const deckTitle = 200;
  static const cardFront = 500;
  static const cardBack = 1000;
  static const quizTitle = 200;
  static const questionPrompt = 500;
  static const option = 200;
  static const explanation = 1000;
  static const minOptions = 2;
  static const maxOptions = 6;
}

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.courseCode,
    this.filePath,
    this.fileName,
    this.resourceId,
    this.resourceTitle,
    this.resourceFilePath,
  });

  final String id;
  final String title;
  final String body;
  final String? courseCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// A PDF the student uploaded (private "study-files" bucket).
  final String? filePath;
  final String? fileName;

  /// A PDF from the library this note studies.
  final String? resourceId;
  final String? resourceTitle;
  final String? resourceFilePath;

  bool get hasUpload => filePath != null;
  bool get hasLibraryPdf => resourceId != null && resourceFilePath != null;
  bool get hasPdf => hasUpload || hasLibraryPdf;

  /// The name to show for the PDF behind this note, if any.
  String? get pdfLabel => hasUpload ? (fileName ?? 'Uploaded PDF') : hasLibraryPdf ? resourceTitle : null;

  static const columns = 'id,title,body,course_code,created_at,updated_at,'
      'file_path,file_name,resource_id,resource:resources(title,file_path)';

  factory Note.fromMap(Map<String, dynamic> m) {
    final res = m['resource'];
    return Note(
      id: m['id'] as String,
      title: (m['title'] ?? '') as String,
      body: (m['body'] ?? '') as String,
      courseCode: m['course_code'] as String?,
      createdAt: _time(m['created_at']),
      updatedAt: _time(m['updated_at']),
      filePath: m['file_path'] as String?,
      fileName: m['file_name'] as String?,
      resourceId: m['resource_id'] as String?,
      resourceTitle: res is Map ? res['title'] as String? : null,
      resourceFilePath: res is Map ? res['file_path'] as String? : null,
    );
  }

  /// The first line or so of the body, for list rows; for a PDF note with
  /// no typed text, the PDF it is built on.
  String get preview {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return pdfLabel == null ? '' : 'PDF: $pdfLabel';
    return flat.length <= 140 ? flat : '${flat.substring(0, 140).trimRight()}...';
  }
}

class Summary {
  const Summary({
    required this.id,
    required this.noteId,
    required this.body,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String noteId;
  final String body;
  final StudySource source;
  final DateTime createdAt;

  static const columns = 'id,note_id,body,source,created_at';

  factory Summary.fromMap(Map<String, dynamic> m) => Summary(
        id: m['id'] as String,
        noteId: m['note_id'] as String,
        body: (m['body'] ?? '') as String,
        source: _source(m['source']),
        createdAt: _time(m['created_at']),
      );
}

/// Reads PostgREST's embedded count, which arrives as [{"count": n}].
int _embeddedCount(Object? v) {
  if (v is List && v.isNotEmpty && v.first is Map) {
    return ((v.first as Map)['count'] as num?)?.toInt() ?? 0;
  }
  return 0;
}

class Deck {
  const Deck({
    required this.id,
    required this.title,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.cardCount,
    this.noteId,
  });

  final String id;
  final String? noteId;
  final String title;
  final StudySource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int cardCount;

  static const columns =
      'id,note_id,title,source,created_at,updated_at,study_flashcards(count)';

  factory Deck.fromMap(Map<String, dynamic> m) => Deck(
        id: m['id'] as String,
        noteId: m['note_id'] as String?,
        title: (m['title'] ?? '') as String,
        source: _source(m['source']),
        createdAt: _time(m['created_at']),
        updatedAt: _time(m['updated_at']),
        cardCount: _embeddedCount(m['study_flashcards']),
      );
}

class Flashcard {
  const Flashcard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.position,
  });

  final String id;
  final String deckId;
  final String front;
  final String back;
  final int position;

  static const columns = 'id,deck_id,front,back,position';

  factory Flashcard.fromMap(Map<String, dynamic> m) => Flashcard(
        id: m['id'] as String,
        deckId: m['deck_id'] as String,
        front: (m['front'] ?? '') as String,
        back: (m['back'] ?? '') as String,
        position: (m['position'] as num?)?.toInt() ?? 0,
      );
}

class QuizScore {
  const QuizScore({required this.score, required this.total, required this.at});
  final int score;
  final int total;
  final DateTime at;

  String get label => '$score/$total';

  factory QuizScore.fromMap(Map<String, dynamic> m) => QuizScore(
        score: (m['score'] as num).toInt(),
        total: (m['total'] as num).toInt(),
        at: _time(m['created_at']),
      );
}

class Quiz {
  const Quiz({
    required this.id,
    required this.title,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.questionCount,
    required this.scores,
    this.noteId,
  });

  final String id;
  final String? noteId;
  final String title;
  final StudySource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int questionCount;

  /// Every attempt's score, newest first.
  final List<QuizScore> scores;

  QuizScore? get latest => scores.isEmpty ? null : scores.first;

  static const columns = 'id,note_id,title,source,created_at,updated_at,'
      'study_quiz_questions(count),study_quiz_attempts(score,total,created_at)';

  factory Quiz.fromMap(Map<String, dynamic> m) {
    final scores = [
      for (final a in (m['study_quiz_attempts'] as List? ?? const []))
        QuizScore.fromMap(a as Map<String, dynamic>),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return Quiz(
      id: m['id'] as String,
      noteId: m['note_id'] as String?,
      title: (m['title'] ?? '') as String,
      source: _source(m['source']),
      createdAt: _time(m['created_at']),
      updatedAt: _time(m['updated_at']),
      questionCount: _embeddedCount(m['study_quiz_questions']),
      scores: scores,
    );
  }
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.quizId,
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.position,
    this.explanation,
  });

  final String id;
  final String quizId;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
  final int position;

  static const columns = 'id,quiz_id,prompt,options,correct_index,explanation,position';

  factory QuizQuestion.fromMap(Map<String, dynamic> m) => QuizQuestion(
        id: m['id'] as String,
        quizId: m['quiz_id'] as String,
        prompt: (m['prompt'] ?? '') as String,
        options: [for (final o in (m['options'] as List? ?? const [])) '$o'],
        correctIndex: (m['correct_index'] as num).toInt(),
        explanation: m['explanation'] as String?,
        position: (m['position'] as num?)?.toInt() ?? 0,
      );
}

/// A finished attempt, as saved and marked by the database.
class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.quizId,
    required this.answers,
    required this.score,
    required this.total,
    required this.createdAt,
  });

  final String id;
  final String quizId;

  /// Question id to the chosen option's position.
  final Map<String, int> answers;
  final int score;
  final int total;
  final DateTime createdAt;

  static const columns = 'id,quiz_id,answers,score,total,created_at';

  factory QuizAttempt.fromMap(Map<String, dynamic> m) => QuizAttempt(
        id: m['id'] as String,
        quizId: m['quiz_id'] as String,
        answers: {
          for (final e in ((m['answers'] as Map?) ?? const {}).entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
        },
        score: (m['score'] as num).toInt(),
        total: (m['total'] as num).toInt(),
        createdAt: _time(m['created_at']),
      );
}

/// Today's AI allowance for the signed-in student.
class AiStatus {
  const AiStatus({required this.used, required this.dailyLimit, required this.remaining});
  final int used;
  final int dailyLimit;
  final int remaining;

  factory AiStatus.fromMap(Map<String, dynamic> m) => AiStatus(
        used: (m['used'] as num?)?.toInt() ?? 0,
        dailyLimit: (m['daily_limit'] as num?)?.toInt() ?? 0,
        remaining: (m['remaining'] as num?)?.toInt() ?? 0,
      );
}

/// What study-generate sends back on success.
class GenerateResult {
  const GenerateResult({
    required this.kind,
    required this.id,
    required this.cached,
    required this.reused,
    required this.remaining,
  });

  final StudyKind kind;
  final String id;

  /// True when the answer came from the cache and Gemini was not asked.
  final bool cached;

  /// True when the item already existed and was returned as is.
  final bool reused;
  final int remaining;

  static GenerateResult? tryParse(Object? data) {
    if (data is! Map) return null;
    final kind = StudyKindX.parse(data['kind']);
    final id = data['id'];
    if (kind == null || id is! String) return null;
    return GenerateResult(
      kind: kind,
      id: id,
      cached: data['cached'] == true,
      reused: data['reused'] == true,
      remaining: (data['remaining'] as num?)?.toInt() ?? 0,
    );
  }
}
