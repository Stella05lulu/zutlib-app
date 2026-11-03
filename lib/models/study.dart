/// The study assistant's data, as the app sees it. Each class mirrors one
/// table in supabase/migrations/0010_study_assistant.sql.
library;

DateTime _time(Object? v) => DateTime.parse(v as String).toLocal();

/// Where a summary, deck or quiz came from.
enum StudySource { manual, ai }

StudySource _source(Object? v) => v == 'ai' ? StudySource.ai : StudySource.manual;

/// What AI can make from a note. [wire] is the value the study-generate
/// function expects in "type". [kit] makes the whole study kit (guide,
/// flashcards and question bank) in one request.
enum StudyKind { summary, flashcards, quiz, kit }

extension StudyKindX on StudyKind {
  String get wire => name;

  static StudyKind? parse(Object? v) => switch (v) {
        'summary' => StudyKind.summary,
        'flashcards' => StudyKind.flashcards,
        'quiz' => StudyKind.quiz,
        'kit' => StudyKind.kit,
        _ => null,
      };
}

/// The colour of a study kit's card. The values match the CHECK constraint
/// in 0014_study_kits.sql.
enum KitColor { blue, red, yellow, green, orange, teal, slate }

extension KitColorX on KitColor {
  String get wire => name;

  String get label => switch (this) {
        KitColor.blue => 'Blue',
        KitColor.red => 'Red',
        KitColor.yellow => 'Yellow',
        KitColor.green => 'Green',
        KitColor.orange => 'Orange',
        KitColor.teal => 'Teal',
        KitColor.slate => 'Slate',
      };

  static KitColor parse(Object? v) =>
      KitColor.values.firstWhere((c) => c.name == v, orElse: () => KitColor.blue);

  /// A colour for a new kit, so a list of kits is not all one colour.
  static KitColor forIndex(int i) => KitColor.values[i % KitColor.values.length];
}

/// YouTube links in every common form, reduced to the one form the
/// database accepts: https://www.youtube.com/watch?v=<11 character id>.
/// Returns null when [input] is not a YouTube video link.
String? normaliseYoutubeUrl(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.|music\.)'), '');
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host == 'youtube.com') {
    final segs = uri.pathSegments;
    if (segs.isNotEmpty && segs.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (segs.length >= 2 && (segs.first == 'shorts' || segs.first == 'live' || segs.first == 'embed')) {
      id = segs[1];
    }
  }
  if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) return null;
  return 'https://www.youtube.com/watch?v=$id';
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
    this.youtubeUrl,
    this.color = KitColor.blue,
  });

  final String id;
  final String title;
  final String body;

  /// The kit's YouTube video, in the standard watch form.
  final String? youtubeUrl;
  final KitColor color;
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
  bool get hasVideo => youtubeUrl != null;

  /// True when there is anything for AI to read.
  bool get hasMaterials => hasPdf || hasVideo || body.trim().isNotEmpty;

  /// What the kit is built on, in a few words, for the kit list.
  String get sourceLabel => hasUpload
      ? 'PDF'
      : hasLibraryPdf
          ? 'Library PDF'
          : hasVideo
              ? 'YouTube video'
              : body.trim().isNotEmpty
                  ? 'Notes'
                  : 'No materials yet';

  /// The name to show for the PDF behind this note, if any.
  String? get pdfLabel => hasUpload ? (fileName ?? 'Uploaded PDF') : hasLibraryPdf ? resourceTitle : null;

  static const columns = 'id,title,body,course_code,created_at,updated_at,'
      'file_path,file_name,resource_id,youtube_url,color,resource:resources(title,file_path)';

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
      youtubeUrl: m['youtube_url'] as String?,
      color: KitColorX.parse(m['color']),
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
    this.difficulty = 2,
  });

  final String id;
  final String quizId;
  final String prompt;

  /// 1 easy, 2 medium, 3 hard.
  final int difficulty;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
  final int position;

  static const columns = 'id,quiz_id,prompt,options,correct_index,explanation,position,difficulty';

  factory QuizQuestion.fromMap(Map<String, dynamic> m) => QuizQuestion(
        id: m['id'] as String,
        quizId: m['quiz_id'] as String,
        prompt: (m['prompt'] ?? '') as String,
        options: [for (final o in (m['options'] as List? ?? const [])) '$o'],
        correctIndex: (m['correct_index'] as num).toInt(),
        explanation: m['explanation'] as String?,
        position: (m['position'] as num?)?.toInt() ?? 0,
        difficulty: (m['difficulty'] as num?)?.toInt() ?? 2,
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
    this.deckId,
    this.quizId,
  });

  final StudyKind kind;
  final String id;

  /// For a kit: the deck and question bank the AI made.
  final String? deckId;
  final String? quizId;

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
      deckId: data['deck_id'] as String?,
      quizId: data['quiz_id'] as String?,
    );
  }
}

// ------------------------------------------------------------------ kits

/// One topic of an AI study guide.
class GuideSection {
  const GuideSection({required this.heading, required this.summary, required this.points});
  final String heading;
  final String summary;
  final List<String> points;

  factory GuideSection.fromMap(Map<String, dynamic> m) => GuideSection(
        heading: (m['heading'] ?? '') as String,
        summary: (m['summary'] ?? '') as String,
        points: [for (final p in (m['points'] as List? ?? const [])) '$p'],
      );
}

/// A kit's AI study guide, with the deck and question bank made with it.
class StudyGuide {
  const StudyGuide({
    required this.id,
    required this.noteId,
    required this.overview,
    required this.sections,
    required this.createdAt,
    this.deckId,
    this.quizId,
  });

  final String id;
  final String noteId;
  final String overview;
  final List<GuideSection> sections;
  final DateTime createdAt;
  final String? deckId;
  final String? quizId;

  static const columns = 'id,note_id,overview,sections,created_at,deck_id,quiz_id';

  factory StudyGuide.fromMap(Map<String, dynamic> m) => StudyGuide(
        id: m['id'] as String,
        noteId: m['note_id'] as String,
        overview: (m['overview'] ?? '') as String,
        sections: [
          for (final s in (m['sections'] as List? ?? const []))
            if (s is Map) GuideSection.fromMap(s.cast<String, dynamic>()),
        ],
        createdAt: _time(m['created_at']),
        deckId: m['deck_id'] as String?,
        quizId: m['quiz_id'] as String?,
      );
}

/// A timed test drawn from a kit's question bank.
class StudyTest {
  const StudyTest({
    required this.id,
    required this.quizId,
    required this.title,
    required this.questionIds,
    required this.difficulty,
    required this.timeLimitSeconds,
    required this.createdAt,
    required this.attempts,
    this.noteId,
  });

  final String id;
  final String? noteId;
  final String quizId;
  final String title;
  final List<String> questionIds;

  /// 'easy', 'mixed' or 'hard'.
  final String difficulty;

  /// 0 means no time limit.
  final int timeLimitSeconds;
  final DateTime createdAt;

  /// Every attempt, newest first.
  final List<TestAttempt> attempts;

  TestAttempt? get best {
    if (attempts.isEmpty) return null;
    return attempts.reduce((a, b) => b.fraction > a.fraction ? b : a);
  }

  static const columns = 'id,note_id,quiz_id,title,question_ids,difficulty,time_limit_s,created_at,'
      'study_test_attempts(id,test_id,answers,score,total,seconds_taken,created_at)';

  factory StudyTest.fromMap(Map<String, dynamic> m) {
    final attempts = [
      for (final a in (m['study_test_attempts'] as List? ?? const []))
        TestAttempt.fromMap(a as Map<String, dynamic>),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return StudyTest(
      id: m['id'] as String,
      noteId: m['note_id'] as String?,
      quizId: m['quiz_id'] as String,
      title: (m['title'] ?? '') as String,
      questionIds: [for (final q in (m['question_ids'] as List? ?? const [])) '$q'],
      difficulty: (m['difficulty'] ?? 'mixed') as String,
      timeLimitSeconds: (m['time_limit_s'] as num?)?.toInt() ?? 0,
      createdAt: _time(m['created_at']),
      attempts: attempts,
    );
  }
}

/// A finished test, marked by the database.
class TestAttempt {
  const TestAttempt({
    required this.id,
    required this.testId,
    required this.answers,
    required this.score,
    required this.total,
    required this.secondsTaken,
    required this.createdAt,
  });

  final String id;
  final String testId;
  final Map<String, int> answers;
  final int score;
  final int total;
  final int secondsTaken;
  final DateTime createdAt;

  double get fraction => total == 0 ? 0 : score / total;
  int get percent => (fraction * 100).round();

  static const columns = 'id,test_id,answers,score,total,seconds_taken,created_at';

  factory TestAttempt.fromMap(Map<String, dynamic> m) => TestAttempt(
        id: m['id'] as String,
        testId: m['test_id'] as String,
        answers: {
          for (final e in ((m['answers'] as Map?) ?? const {}).entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
        },
        score: (m['score'] as num).toInt(),
        total: (m['total'] as num).toInt(),
        secondsTaken: (m['seconds_taken'] as num?)?.toInt() ?? 0,
        createdAt: _time(m['created_at']),
      );
}

/// The two flashcard games.
enum GameKind { matching, trueFalse }

extension GameKindX on GameKind {
  String get wire => this == GameKind.matching ? 'matching' : 'true_false';
  String get label => this == GameKind.matching ? 'Matching' : 'True or false';

  static GameKind? parse(Object? v) => switch (v) {
        'matching' => GameKind.matching,
        'true_false' => GameKind.trueFalse,
        _ => null,
      };
}

class GameScore {
  const GameScore({required this.score, required this.seconds, required this.at});
  final int score;
  final int seconds;
  final DateTime at;

  static const columns = 'score,seconds,created_at';

  factory GameScore.fromMap(Map<String, dynamic> m) => GameScore(
        score: (m['score'] as num).toInt(),
        seconds: (m['seconds'] as num).toInt(),
        at: _time(m['created_at']),
      );
}
