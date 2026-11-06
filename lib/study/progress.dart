// My progress: scores over time and what to revise next. Plain rules, no
// AI, so every suggestion can be explained in one line.
//
//   scoreSeries   one point per attempt (test or quiz), as a percentage,
//                 oldest first, for one kit, one course or everything
//   reviseNext    the questions a student gets wrong most often lately:
//                 for each question, its last four tries; a question is
//                 suggested when at least half of those were wrong. Most
//                 often wrong first, then most wrong tries, then the most
//                 recent mistake.
//   attemptStreak days in a row, up to today, with at least one attempt

/// One test or quiz attempt.
class AttemptRecord {
  const AttemptRecord({
    required this.at,
    required this.score,
    required this.total,
    required this.answers,
    this.noteId,
    this.courseCode,
  });

  final DateTime at;
  final int score;
  final int total;

  /// Question id to the option chosen.
  final Map<String, int> answers;
  final String? noteId;
  final String? courseCode;

  double get percent => total <= 0 ? 0 : score / total;
}

class QuestionInfo {
  const QuestionInfo({required this.id, required this.prompt, required this.correctIndex, this.noteId});
  final String id;
  final String prompt;
  final int correctIndex;
  final String? noteId;
}

class ScorePoint {
  const ScorePoint(this.at, this.percent);
  final DateTime at;
  final double percent;
}

class ReviseItem {
  const ReviseItem({
    required this.question,
    required this.wrong,
    required this.tries,
    required this.lastWrong,
  });

  final QuestionInfo question;
  final int wrong;
  final int tries;
  final DateTime lastWrong;

  /// "Wrong in 3 of your last 4 tries".
  String get reason {
    if (tries == 1) return 'Wrong the only time you tried it';
    if (wrong == tries) return 'Wrong in all of your last $tries tries';
    return 'Wrong in $wrong of your last $tries tries';
  }
}

/// Scores oldest first, filtered to one kit or one course when given.
List<ScorePoint> scoreSeries(Iterable<AttemptRecord> attempts, {String? noteId, String? courseCode}) {
  final picked = attempts
      .where((a) => a.total > 0)
      .where((a) => noteId == null || a.noteId == noteId)
      .where((a) => courseCode == null || normaliseCode(a.courseCode) == normaliseCode(courseCode))
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  return [for (final a in picked) ScorePoint(a.at, a.percent)];
}

/// The average of the last [n] points and the [n] before them, to say
/// whether scores are going up. Null when there are not enough points.
double? recentChange(List<ScorePoint> points, {int n = 3}) {
  if (points.length < 2 * n) return null;
  double avg(Iterable<ScorePoint> p) => p.map((x) => x.percent).reduce((a, b) => a + b) / p.length;
  final last = points.sublist(points.length - n);
  final before = points.sublist(points.length - 2 * n, points.length - n);
  return avg(last) - avg(before);
}

/// The questions to revise next, worst first.
List<ReviseItem> reviseNext(
  Iterable<AttemptRecord> attempts,
  Map<String, QuestionInfo> questions, {
  int window = 4,
  int limit = 5,
}) {
  final history = <String, List<(DateTime, bool)>>{};
  for (final a in attempts) {
    for (final e in a.answers.entries) {
      final q = questions[e.key];
      if (q == null) continue; // Deleted since.
      (history[e.key] ??= []).add((a.at, e.value == q.correctIndex));
    }
  }
  final items = <ReviseItem>[];
  history.forEach((id, tries) {
    tries.sort((a, b) => b.$1.compareTo(a.$1)); // Newest first.
    final recent = tries.take(window).toList();
    final wrong = recent.where((t) => !t.$2).toList();
    if (wrong.isEmpty || wrong.length * 2 < recent.length) return;
    items.add(ReviseItem(question: questions[id]!, wrong: wrong.length, tries: recent.length, lastWrong: wrong.first.$1));
  });
  items.sort((a, b) {
    final ratio = (b.wrong / b.tries).compareTo(a.wrong / a.tries);
    if (ratio != 0) return ratio;
    final count = b.wrong.compareTo(a.wrong);
    if (count != 0) return count;
    return b.lastWrong.compareTo(a.lastWrong);
  });
  return items.take(limit).toList();
}

/// Days in a row with at least one attempt, ending today, or yesterday if
/// nothing has been done yet today.
int attemptStreak(Iterable<DateTime> attemptTimes, DateTime now) {
  final days = {for (final t in attemptTimes) DateTime(t.year, t.month, t.day)};
  var day = DateTime(now.year, now.month, now.day);
  if (!days.contains(day)) day = day.subtract(const Duration(days: 1));
  var n = 0;
  while (days.contains(day)) {
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

/// "eee2011", "EEE 2011" and "EEE2011" are the same course.
String normaliseCode(String? code) => (code ?? '').toUpperCase().replaceAll(RegExp(r'\s+'), '');
