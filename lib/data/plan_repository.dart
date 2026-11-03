import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';
import '../core/supabase.dart';
import '../models/plan.dart';
import '../study/planner.dart';

/// Study plans, hand ticks, daily activity and guide reading. Row level
/// security returns only the signed-in student's rows; the app never sends
/// a user id.
class PlanRepository {
  const PlanRepository();

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      if (e.code == '22023' || e.code == '54000') throw Failure(e.message);
      if (e.code == '23505') throw const Failure('This kit already has a plan. Open it to change the date.');
      throw Failure.from(e);
    } catch (e) {
      if (e is Failure) rethrow;
      throw Failure.from(e);
    }
  }

  // ------------------------------------------------------------- plans
  Future<List<StudyPlan>> plans() => _guard(() async {
        final data = await db.from('study_plans').select(StudyPlan.columns).order('exam_date');
        return [for (final r in data as List) StudyPlan.fromMap(r as Map<String, dynamic>)];
      });

  Future<StudyPlan?> plan(String id) => _guard(() async {
        final data = await db.from('study_plans').select(StudyPlan.columns).eq('id', id).maybeSingle();
        return data == null ? null : StudyPlan.fromMap(data);
      });

  Future<StudyPlan> create({
    required String noteId,
    required DateTime examDate,
    required int studyDays,
    required int minutes,
  }) =>
      _guard(() async {
        final data = await db
            .from('study_plans')
            .insert({
              'note_id': noteId,
              'exam_date': isoDate(examDate),
              'study_days': studyDays,
              'minutes': minutes,
            })
            .select(StudyPlan.columns)
            .single();
        return StudyPlan.fromMap(data);
      });

  Future<void> update(String id, {required DateTime examDate, required int studyDays, required int minutes}) =>
      _guard(() async {
        await db.from('study_plans').update({
          'exam_date': isoDate(examDate),
          'study_days': studyDays,
          'minutes': minutes,
        }).eq('id', id);
      });

  Future<void> delete(String id) => _guard(() async {
        await db.from('study_plans').delete().eq('id', id);
      });

  // ------------------------------------------------------------- hand ticks
  /// Task keys ticked by hand on [day], per plan.
  Future<Map<String, Set<String>>> checks(DateTime day) => _guard(() async {
        final data = await db.from('study_plan_checks').select('plan_id,task_key').eq('day', isoDate(day));
        final out = <String, Set<String>>{};
        for (final r in data as List) {
          final m = r as Map<String, dynamic>;
          (out[m['plan_id'] as String] ??= {}).add(m['task_key'] as String);
        }
        return out;
      });

  Future<void> setCheck(String planId, DateTime day, String taskKey, bool done) => _guard(() async {
        if (done) {
          await db.from('study_plan_checks').upsert(
            {'plan_id': planId, 'day': isoDate(day), 'task_key': taskKey},
            ignoreDuplicates: true,
          );
        } else {
          await db
              .from('study_plan_checks')
              .delete()
              .eq('plan_id', planId)
              .eq('day', isoDate(day))
              .eq('task_key', taskKey);
        }
      });

  // ------------------------------------------------------------- activity
  /// Kit id to day to what was done, from [since] on.
  Future<Map<String, Map<DateTime, DayActivity>>> activity(DateTime since) => _guard(() async {
        final data = await db
            .from('study_activity')
            .select('note_id,day,kind,amount')
            .gte('day', isoDate(since));
        final raw = <String, Map<DateTime, Map<String, int>>>{};
        for (final r in data as List) {
          final m = r as Map<String, dynamic>;
          final day = dateOnly(DateTime.parse(m['day'] as String));
          final kinds = (raw[m['note_id'] as String] ??= {})[day] ??= {};
          kinds[m['kind'] as String] = ((m['amount'] as num?) ?? 0).toInt();
        }
        return {
          for (final e in raw.entries)
            e.key: {
              for (final d in e.value.entries)
                d.key: DayActivity(
                  cards: d.value['cards'] ?? 0,
                  questions: d.value['questions'] ?? 0,
                  tests: d.value['test'] ?? 0,
                  guide: d.value['guide'] ?? 0,
                ),
            },
        };
      });

  // ------------------------------------------------------------- guide reading
  /// Guide id to section to the day it was read.
  Future<Map<String, Map<int, DateTime>>> reads(List<String> guideIds) => _guard(() async {
        if (guideIds.isEmpty) return <String, Map<int, DateTime>>{};
        final data = await db
            .from('study_guide_reads')
            .select('guide_id,section,read_at')
            .inFilter('guide_id', guideIds);
        final out = <String, Map<int, DateTime>>{};
        for (final r in data as List) {
          final m = r as Map<String, dynamic>;
          (out[m['guide_id'] as String] ??= {})[((m['section'] as num?) ?? 0).toInt()] =
              DateTime.parse(m['read_at'] as String).toLocal();
        }
        return out;
      });

  Future<void> markRead(String guideId, int section) => _guard(() async {
        await db.rpc('study_mark_read', params: {'p_guide': guideId, 'p_section': section});
      });

  Future<void> unmarkRead(String guideId, int section) => _guard(() async {
        await db.from('study_guide_reads').delete().eq('guide_id', guideId).eq('section', section);
      });
}
