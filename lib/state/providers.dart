import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../data/admin_repository.dart';
import '../data/auth_repository.dart';
import '../data/borrow_repository.dart';
import '../data/library_repository.dart';
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
const libraryRepo = LibraryRepository();
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
  final profile = ref.watch(profileProvider).valueOrNull;
  return switch (profile?.role) {
    UserRole.admin => '/admin',
    UserRole.librarian => '/staff/requests',
    _ => '/browse',
  };
});

/// An email link the app was opened with (invite, password reset or
/// address confirmation), waiting to be turned into a session. See
/// main.dart, SplashScreen and supabase/templates/.
class EmailLink {
  const EmailLink(this.type, this.tokenHash);

  /// 'invite', 'recovery' or 'signup'.
  final String type;
  final String tokenHash;

  /// The link types the email templates produce.
  static const types = {'invite', 'recovery', 'signup'};

  /// Supabase sends people back with ?error_code=... when a link it checked
  /// itself (an older email) had expired or was already used.
  static const failed = 'failed';

  /// Reads ?token_hash=...&type=... (or Supabase's ?error_code=...) from the
  /// address the app was opened at.
  static EmailLink? fromUri(Uri uri) {
    final error = uri.queryParameters['error_code'] ?? uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) return EmailLink(failed, error);
    final type = uri.queryParameters['type'];
    final hash = uri.queryParameters['token_hash'];
    if (type == null || hash == null || hash.isEmpty || !types.contains(type)) return null;
    return EmailLink(type, hash);
  }
}

final pendingEmailLinkProvider = StateProvider<EmailLink?>((_) => null);

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

/// One screenful of search results, and whether the database has more.
class SearchPage {
  const SearchPage(this.items, {required this.hasMore});
  final List<Resource> items;
  final bool hasMore;
}

const searchPageSize = 50;

/// Search results arrive [searchPageSize] at a time. Changing the filters
/// starts again from the first page; [SearchResults.loadMore] adds the next.
class SearchResults extends AsyncNotifier<SearchPage> {
  @override
  Future<SearchPage> build() {
    ref.watch(userIdProvider);
    return _page(ref.watch(filtersProvider), 0);
  }

  /// Asks for one row more than a page, so the extra row says whether
  /// another page exists without a separate count.
  static Future<SearchPage> _page(ResourceFilters f, int offset) async {
    final rows = await resourceRepo.search(f, limit: searchPageSize + 1, offset: offset);
    return SearchPage(rows.take(searchPageSize).toList(), hasMore: rows.length > searchPageSize);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final filters = ref.read(filtersProvider);
    final next = await _page(filters, current.items.length);
    // The filters changed while this page loaded; it belongs to an old search.
    if (state.valueOrNull != current || ref.read(filtersProvider) != filters) return;
    state = AsyncData(SearchPage([...current.items, ...next.items], hasMore: next.hasMore));
  }
}

final searchProvider = AsyncNotifierProvider<SearchResults, SearchPage>(SearchResults.new);

/// The Explore home: a few of each type, fetched per type so a type with
/// few items still gets its shelf next to one with hundreds.
final homeShelvesProvider = FutureProvider<Map<ResourceType, List<Resource>>>((ref) async {
  ref.watch(userIdProvider);
  final lists = await Future.wait([
    for (final type in ResourceType.values) resourceRepo.search(ResourceFilters(type: type), limit: 12),
  ]);
  return {
    for (var i = 0; i < ResourceType.values.length; i++)
      if (lists[i].isNotEmpty) ResourceType.values[i]: lists[i],
  };
});

final resourceProvider =
    FutureProvider.family<Resource, String>((ref, id) => resourceRepo.byId(id));

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
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.where((n) => n.isUnread).length;
});

// ------------------------------------------------------------------ admin
final adminOverviewProvider = FutureProvider.autoDispose<AdminOverview>((ref) {
  ref.watch(userIdProvider);
  return adminRepo.overview();
});

/// Which list the Users screen shows: pending students, or everyone.
final usersTabProvider = StateProvider<int>((_) => 0);
final usersSearchProvider = StateProvider<String>((_) => '');

final pendingUsersProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  ref.watch(userIdProvider);
  return adminRepo.users(status: AccountStatus.pending);
});

final usersProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  ref.watch(userIdProvider);
  return adminRepo.users(search: ref.watch(usersSearchProvider));
});

final auditProvider = FutureProvider.autoDispose<List<AuditEntry>>((ref) {
  ref.watch(userIdProvider);
  return adminRepo.audit();
});

void refreshUsers(WidgetRef ref) {
  ref.invalidate(pendingUsersProvider);
  ref.invalidate(usersProvider);
  ref.invalidate(adminOverviewProvider);
  ref.invalidate(auditProvider);
}

// ------------------------------------------------------------------ library (staff)
/// 0 = papers and notes, 1 = books, 2 = recommended books.
final libraryTabProvider = StateProvider<int>((_) => 0);
final libraryQueryProvider = StateProvider<String>((_) => '');
final libraryShowRetiredProvider = StateProvider<bool>((_) => false);

/// How many rows the staff list shows. Starts again at one page whenever
/// the tab, search or retired filter changes.
const libraryPageSize = 100;
final libraryLimitProvider = StateProvider<int>((ref) {
  ref.watch(libraryTabProvider);
  ref.watch(libraryQueryProvider);
  ref.watch(libraryShowRetiredProvider);
  return libraryPageSize;
});

final libraryItemsProvider = FutureProvider.autoDispose<SearchPage>((ref) async {
  ref.watch(userIdProvider);
  final limit = ref.watch(libraryLimitProvider);
  final rows = await libraryRepo.list(
    types: switch (ref.watch(libraryTabProvider)) {
      1 => const [ResourceType.book],
      2 => const [ResourceType.bookLink],
      _ => const [ResourceType.pastPaper, ResourceType.testPaper, ResourceType.lectureNotes],
    },
    query: ref.watch(libraryQueryProvider),
    includeRetired: ref.watch(libraryShowRetiredProvider),
    limit: limit + 1,
  );
  return SearchPage(rows.take(limit).toList(), hasMore: rows.length > limit);
});

/// Called after any write so every view showing the affected data refreshes.
void refreshBorrowing(WidgetRef ref) {
  ref.invalidate(myBorrowingProvider);
  ref.invalidate(queueProvider);
  ref.invalidate(overviewProvider);
  ref.invalidate(notificationsProvider);
  refreshCatalogue(ref);
}

/// Called after the catalogue changes, so student and staff views agree.
void refreshCatalogue(WidgetRef ref) {
  ref.invalidate(searchProvider);
  ref.invalidate(homeShelvesProvider);
  ref.invalidate(libraryItemsProvider);
}
