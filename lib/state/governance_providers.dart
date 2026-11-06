import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_repository.dart' show AuditEntry;
import '../data/governance_repository.dart';
import '../models/profile.dart';
import '../models/resource.dart';
import '../study/audit_stats.dart';
import 'providers.dart';

// ------------------------------------------------------------------ settings
final settingsProvider = FutureProvider.autoDispose<SystemSettings>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.settings();
});

// ------------------------------------------------------------------ announcements
final announcementsProvider = FutureProvider.autoDispose<List<Announcement>>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.announcements();
});

/// The newest announcement this person can see (students only ever get
/// active ones; administrators may also see ended ones, which are skipped).
final latestAnnouncementProvider = Provider.autoDispose<Announcement?>((ref) {
  final list = ref.watch(announcementsProvider).valueOrNull ?? const [];
  for (final a in list) {
    if (!a.hasEnded) return a;
  }
  return null;
});

// ------------------------------------------------------------------ saved
final savedProvider = FutureProvider.autoDispose<List<Resource>>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.saved();
});

final recentResourcesProvider = FutureProvider.autoDispose<List<Resource>>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.recent();
});

final savedIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  return {for (final r in ref.watch(savedProvider).valueOrNull ?? const <Resource>[]) r.id};
});

// ------------------------------------------------------------------ admin
final adminBadgesProvider = FutureProvider.autoDispose<AdminBadges>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null || !profile.role.isAdmin) return const AdminBadges();
  return governanceRepo.badges();
});

final dashboardMonthlyProvider = StateProvider<bool>((_) => false);

final adminDashboardProvider = FutureProvider.autoDispose<AdminDashboardData>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.dashboard(monthly: ref.watch(dashboardMonthlyProvider));
});

/// Audit log filters: an action prefix (null = everything) and a search.
final auditCategoryProvider = StateProvider<String?>((_) => null);
final auditSearchProvider = StateProvider<String>((_) => '');

final auditLogProvider = FutureProvider.autoDispose<List<AuditEntry>>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.audit(category: ref.watch(auditCategoryProvider), search: ref.watch(auditSearchProvider));
});

/// The last seven days of the audit log as activity figures.
final auditStatsProvider = FutureProvider.autoDispose<AuditStats>((ref) async {
  ref.watch(userIdProvider);
  return AuditStats.from(await governanceRepo.auditWeek(), DateTime.now());
});

/// Invited people who have not chosen a password yet.
final invitationsProvider = FutureProvider.autoDispose<List<Profile>>((ref) async {
  ref.watch(userIdProvider);
  final everyone = await adminRepo.users();
  return [for (final p in everyone) if (p.mustSetPassword && p.status != AccountStatus.removed) p];
});

final userDetailProvider = FutureProvider.autoDispose.family<Profile?, String>((ref, id) {
  ref.watch(userIdProvider);
  return adminRepo.user(id);
});

void refreshAdmin(WidgetRef ref) {
  refreshUsers(ref);
  ref.invalidate(adminBadgesProvider);
  ref.invalidate(adminDashboardProvider);
  ref.invalidate(auditLogProvider);
  ref.invalidate(auditStatsProvider);
  ref.invalidate(invitationsProvider);
  ref.invalidate(userDetailProvider);
}

// ------------------------------------------------------------------ librarian
final libraryTodayProvider = FutureProvider.autoDispose<LibraryToday>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.today();
});

// ------------------------------------------------------------------ kit sources
final kitSourcesProvider = FutureProvider.autoDispose.family<List<KitSource>, String>((ref, noteId) {
  ref.watch(userIdProvider);
  return governanceRepo.kitSources(noteId);
});

// ------------------------------------------------------------------ progress
final progressDataProvider = FutureProvider.autoDispose<ProgressData>((ref) {
  ref.watch(userIdProvider);
  return governanceRepo.progress();
});
