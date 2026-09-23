import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../data/admin_repository.dart';
import '../data/auth_repository.dart';
import '../data/borrow_repository.dart';
import '../data/resource_repository.dart';
import '../models/borrow_request.dart';
import '../models/profile.dart';
import '../models/resource.dart';

const authRepo = AuthRepository();
const resourceRepo = ResourceRepository();
const borrowRepo = BorrowRepository();
const adminRepo = AdminRepository();

/// Auth events drive everything downstream: a sign in or sign out
/// invalidates the profile, which redirects the router.
final authStateProvider = StreamProvider<AuthState>((ref) => authRepo.changes);

final profileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateProvider);
  if (currentUserId == null) return null;
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
  final department = ref.watch(filtersProvider.select((f) => f.department));
  return resourceRepo.facets(department: department);
});

final searchProvider = FutureProvider<List<Resource>>((ref) {
  final filters = ref.watch(filtersProvider);
  return resourceRepo.search(filters);
});

final resourceProvider =
    FutureProvider.family<Resource, String>((ref, id) => resourceRepo.byId(id));

// ------------------------------------------------------------------ borrow
final myBorrowingProvider =
    FutureProvider<List<BorrowRequest>>((ref) => borrowRepo.mine());

final queueFilterProvider =
    StateProvider<Set<BorrowStatus>>((_) => {BorrowStatus.submitted, BorrowStatus.underReview});

final queueProvider = FutureProvider<List<BorrowRequest>>((ref) {
  final statuses = ref.watch(queueFilterProvider);
  return borrowRepo.queue(statuses: statuses);
});

final overviewProvider =
    FutureProvider<StaffOverview>((ref) => borrowRepo.overview());

// ------------------------------------------------------------------ admin
final rollSearchProvider = StateProvider<String>((_) => '');

final rollProvider = FutureProvider<List<RollEntry>>((ref) {
  final search = ref.watch(rollSearchProvider);
  return adminRepo.roll(search: search);
});

final usersProvider = FutureProvider<List<Profile>>((ref) => adminRepo.users());

/// Called after any write so every view showing the affected data refreshes.
void refreshBorrowing(WidgetRef ref) {
  ref.invalidate(myBorrowingProvider);
  ref.invalidate(queueProvider);
  ref.invalidate(overviewProvider);
  ref.invalidate(searchProvider);
}
