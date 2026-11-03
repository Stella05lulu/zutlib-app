/// "For your courses": which catalogue items to put in front of a student,
/// and the one-line reason shown under each. Simple, explainable rules
/// instead of AI, so every suggestion can say why it is there. Plain Dart,
/// covered by test/recommend_test.dart.
library;

import 'planner.dart' show daysBetween;

/// Course codes are compared the way the database stores them: trimmed,
/// upper case, single spaces ("eee  2011" is "EEE 2011").
String normaliseCourse(String code) => code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

/// The year level of a course from the first digit of its number:
/// "EEE 2011" is a year 2 course. Null when the code has no number.
int? courseLevel(String code) {
  final m = RegExp(r'(\d)\d{2,3}').firstMatch(code);
  return m == null ? null : int.parse(m.group(1)!);
}

/// What the app knows about the student.
class RecProfile {
  const RecProfile({
    this.courses = const {},
    this.department,
    this.yearOfStudy,
    this.examDates = const {},
    this.recentCourses = const {},
  });

  /// Courses they take (from onboarding or Edit profile).
  final Set<String> courses;
  final String? department;
  final int? yearOfStudy;

  /// Course code to exam date, from their study plans.
  final Map<String, DateTime> examDates;

  /// Courses they opened or studied lately.
  final Set<String> recentCourses;

  bool get isEmpty =>
      courses.isEmpty && examDates.isEmpty && recentCourses.isEmpty && (department == null || yearOfStudy == null);
}

/// One catalogue item, as far as recommendations care.
class RecItem<T> {
  const RecItem({required this.item, required this.courseCode, this.department, this.academicYear});
  final T item;
  final String? courseCode;
  final String? department;
  final int? academicYear;
}

class Recommendation<T> {
  const Recommendation(this.item, this.score, this.reason);
  final T item;
  final double score;
  final String reason;
}

/// Scores each item and returns the best [limit], highest first. An item
/// that matches nothing about the student is left out.
///
///   exam coming up for that course   100, plus up to 60 as it gets close
///   a course the student takes        60
///   a course studied recently         25
///   same department and year level    15
///   newer papers break ties
List<Recommendation<T>> recommend<T>(List<RecItem<T>> items, RecProfile p, DateTime today, {int limit = 12}) {
  final courses = p.courses.map(normaliseCourse).toSet();
  final recent = p.recentCourses.map(normaliseCourse).toSet();
  final exams = {for (final e in p.examDates.entries) normaliseCourse(e.key): e.value};

  final out = <Recommendation<T>>[];
  for (final it in items) {
    final code = it.courseCode == null ? '' : normaliseCourse(it.courseCode!);
    var score = 0.0;
    String? reason;

    final exam = exams[code];
    if (code.isNotEmpty && exam != null) {
      final n = daysBetween(today, exam);
      if (n >= 0) {
        score += 100 + (30 - n).clamp(0, 30) * 2;
        reason = n == 0
            ? 'Your $code exam is today'
            : n == 1
                ? 'Your $code exam is tomorrow'
                : 'Your $code exam is in $n days';
      }
    }
    if (code.isNotEmpty && courses.contains(code)) {
      score += 60;
      reason ??= 'Because you take $code';
    }
    if (code.isNotEmpty && recent.contains(code)) {
      score += 25;
      reason ??= 'Because you studied $code recently';
    }
    if (p.department != null &&
        p.yearOfStudy != null &&
        it.department == p.department &&
        code.isNotEmpty &&
        courseLevel(code) == p.yearOfStudy) {
      score += 15;
      reason ??= 'For ${p.department} year ${p.yearOfStudy} students';
    }
    if (score == 0 || reason == null) continue;
    // Newer papers first among equals: 2025 scores a little above 2019.
    score += ((it.academicYear ?? 2000) - 2000).clamp(0, 99) / 100;
    out.add(Recommendation(it.item, score, reason));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.take(limit).toList();
}
