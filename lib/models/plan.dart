import '../study/planner.dart';

/// One exam plan for one study kit (study_plans).
class StudyPlan {
  const StudyPlan({
    required this.id,
    required this.noteId,
    required this.examDate,
    required this.studyDays,
    required this.minutes,
    required this.startDate,
  });

  final String id;
  final String noteId;
  final DateTime examDate;
  final int studyDays;
  final int minutes;
  final DateTime startDate;

  static const columns = 'id,note_id,exam_date,study_days,minutes,start_date';

  PlanSettings get settings =>
      PlanSettings(examDate: examDate, startDate: startDate, studyDays: studyDays, minutes: minutes);

  factory StudyPlan.fromMap(Map<String, dynamic> m) => StudyPlan(
        id: m['id'] as String,
        noteId: m['note_id'] as String,
        examDate: DateTime.parse(m['exam_date'] as String),
        studyDays: ((m['study_days'] as num?) ?? StudyDays.all).toInt(),
        minutes: ((m['minutes'] as num?) ?? 30).toInt(),
        startDate: DateTime.parse(m['start_date'] as String),
      );
}

/// The minute options offered for a daily session.
const kPlanMinutes = [15, 30, 45, 60, 90];

/// A date as the database wants it: 2026-11-20.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
