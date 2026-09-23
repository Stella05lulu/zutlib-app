import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../data/admin_repository.dart';
import '../data/auth_repository.dart';
import '../data/borrow_repository.dart';
import '../data/notification_repository.dart';
import '../data/resource_repository.dart';
import '../models/app_notification.dart';
import '../models/borrow_request.dart';
import '../models/profile.dart';
import '../models/resource.dart';

const authRepo = AuthRepository();
const resourceRepo = ResourceRepository();
const borrowRepo = BorrowRepository();
const adminRepo = AdminRepository();
const notificationRepo = NotificationRepository();

/// Auth events drive everything downstream: a sign in or sign out
/// invalidates the profile, which redirects the router.
final authStateProvider = StreamProvider<AuthState>((ref) => authRepo.changes);

/// The signed-in account's id. Every provider that loads someone's data
/// watches this, so signing out and in as another person never shows the
/// previous person's cached requests, notifications or roles. Token
/// refreshes keep the same id, so they do not trigger reloads.
final userIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return currentUserId;
});

final profileProvider = FutureProvider<Profile?>((ref) async {
  final id = ref.watch(userIdProvider);
  if (id == null) return null;
  return authRepo.loadProfile();
});

/// Where a signed-in person should land, given their role.
final homeRouteProvider = Provider<String>((ref) {
  final profile = ref.watch(profileProvider).value;
  return switch (profile?.role) {
    UserRole.admin => '/admin/roll',
    UserRole.librarian => '/staff/requests',
    _ => '/browse',
  };
});

/// True while the app was opened from a password reset link and the new
/// password has not been set yet. The router keeps the person on the
/// reset screen until it is.
final passwordRecoveryProvider = StateProvider<bool>((_) => false);

// ------------------------------------------------------------------ search
final filtersProvider = StateProvider<ResourceFilters>((_) => const ResourceFilters());

final facetsProvider = FutureProvider<Facets>((ref) {
  ref.watch(userIdProvider);
  final department = ref.watch(filtersProvider.select((f) => f.department));
  return resourceRepo.facets(department: department);
});

final searchProvider = FutureProvider<List<Resource>>((ref) {
  ref.watch(userIdProvider);
  final filters = ref.watch(filtersProvider);
  return resourceRepo.search(filters);
});

final resourceProvider =
    FutureProvider.family<Resource, String>((ref, id) => resourceRepo.byId(id));

// ------------------------------------------------------------------ staff catalogue
/// The staff Resources screen has its own search box, separate from the
/// student Explore filters, and a higher limit.
final staffQueryProvider = StateProvider<String>((_) => '');

final staffResourcesProvider = FutureProvider<List<Resource>>((ref) {
  ref.watch(userIdProvider);
  final q = ref.watch(staffQueryProvider);
  return resourceRepo.search(ResourceFilters(query: q), limit: 100);
});

// ------------------------------------------------------------------ borrow
final myBorrowingProvider = FutureProvider<List<BorrowRequest>>((ref) {
  ref.watch(userIdProvider);
  return borrowRepo.mine();
});

final queueFilterProvider =
    StateProvider<Set<BorrowStatus>>((_) => {BorrowStatus.submitted, BorrowStatus.underReview});

final queueProvider = FutureProvider<List<BorrowRequest>>((ref) {
  ref.watch(userIdProvider);
  final statuses = ref.watch(queueFilterProvider);
  return borrowRepo.queue(statuses: statuses);
});

final overviewProvider = FutureProvider<StaffOverview>((ref) {
  ref.watch(userIdProvider);
  return borrowRepo.overview();
});

// ------------------------------------------------------------------ notifications
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(userIdProvider);
  return notificationRepo.mine();
});

/// Drives the dot on the Updates tab.
final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value ?? const [];
  return list.where((n) => n.isUnread).length;
});

// ------------------------------------------------------------------ admin
final rollSearchProvider = StateProvider<String>((_) => '');

final rollProvider = FutureProvider<List<RollEntry>>((ref) {
  ref.watch(userIdProvider);
  final search = ref.watch(rollSearchProvider);
  return adminRepo.roll(search: search);
});

final usersProvider = FutureProvider<List<Profile>>((ref) {
  ref.watch(userIdProvider);
  return adminRepo.users();
});

/// Called after any write so every view showing the affected data refreshes.
void refreshBorrowing(WidgetRef ref) {
  ref.invalidate(myBorrowingProvider);
  ref.invalidate(queueProvider);
  ref.invalidate(overviewProvider);
  ref.invalidate(searchProvider);
  ref.invalidate(staffResourcesProvider);
  ref.invalidate(notificationsProvider);
}
