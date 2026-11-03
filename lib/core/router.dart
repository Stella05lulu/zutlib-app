import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../state/providers.dart';
import '../models/profile.dart';
import '../ui/screens/auth/forgot_password_screen.dart';
import '../ui/screens/auth/login_screen.dart';
import '../ui/screens/auth/pending_screen.dart';
import '../ui/screens/auth/register_screen.dart';
import '../ui/screens/auth/reset_password_screen.dart';
import '../ui/screens/auth/set_password_screen.dart';
import '../ui/screens/auth/verify_email_screen.dart';
import '../ui/screens/admin/admin_dashboard_screen.dart';
import '../ui/screens/admin/create_account_screen.dart';
import '../ui/screens/admin/reports_screen.dart';
import '../ui/screens/admin/users_screen.dart';
import '../ui/screens/plan/plan_detail_screen.dart';
import '../ui/screens/plan/plan_home_screen.dart';
import '../ui/screens/shared/onboarding_screen.dart';
import '../ui/screens/shared/profile_edit_screen.dart';
import '../ui/screens/shared/profile_screen.dart';
import '../ui/screens/shared/splash_screen.dart';
import '../ui/screens/staff/book_form_screen.dart';
import '../ui/screens/staff/book_import_screen.dart';
import '../ui/screens/staff/library_screen.dart';
import '../ui/screens/staff/link_form_screen.dart';
import '../ui/screens/staff/paper_form_screen.dart';
import '../ui/screens/staff/paper_upload_screen.dart';
import '../ui/screens/staff/request_detail_screen.dart';
import '../ui/screens/staff/request_queue_screen.dart';
import '../ui/screens/student/borrow_request_screen.dart';
import '../ui/screens/student/browse_screen.dart';
import '../ui/screens/student/my_borrowing_screen.dart';
import '../ui/screens/student/notifications_screen.dart';
import '../ui/screens/student/resource_detail_screen.dart';
import '../ui/screens/study/deck_screen.dart';
import '../ui/screens/study/deck_study_screen.dart';
import '../models/study.dart' show GameKind, GameKindX;
import '../ui/screens/study/kit_games_screen.dart';
import '../ui/screens/study/kit_screen.dart';
import '../ui/screens/study/note_editor_screen.dart';
import '../ui/screens/study/quiz_screen.dart';
import '../ui/screens/study/quiz_take_screen.dart';
import '../ui/screens/study/study_home_screen.dart';
import '../ui/screens/study/test_take_screen.dart';
import '../ui/widgets/shell.dart';
import 'supabase.dart';

/// Screens only an approved student uses. Staff are sent home instead.
bool _studentOnly(String path) =>
    path.startsWith('/borrowing') ||
    path.startsWith('/plan') ||
    path.startsWith('/welcome') ||
    path.startsWith('/study') ||
    RegExp(r'^/resource/[^/]+/borrow$').hasMatch(path);

/// One gate, asked in order on every navigation: is anyone signed in, is
/// the address verified, does the account have a profile, has an invited
/// person chosen a password, is the account approved, and does their role
/// cover this screen? The database enforces every one of these again; the
/// app only decides which screen to show.
final routerProvider = Provider<GoRouter>((ref) {
  final shellKey = GlobalKey<NavigatorState>();

  return GoRouter(
    initialLocation: '/',
    // Always start at the splash screen, which decides where to go. Email
    // links (password reset, invites) come back with extra text after the
    // # in the address, such as tokens; read as a screen path, that text
    // crashed the router.
    overridePlatformDefaultLocation: true,
    refreshListenable: _Refresh(ref),
    redirect: (context, state) {
      final path = state.uri.path;

      // Opened from a reset link: nothing else until a new password is set.
      if (ref.read(passwordRecoveryProvider)) {
        return path == '/reset-password' ? null : '/reset-password';
      }
      final signedIn = auth.currentSession != null;
      final onAuthScreen = path == '/login' ||
          path == '/register' ||
          path == '/forgot-password' ||
          path == '/reset-password' ||
          path == '/verify';

      if (path == '/') return null;

      if (!signedIn) return onAuthScreen ? null : '/login';

      if (!isVerified) return path == '/verify' ? null : '/verify';

      final profileAsync = ref.read(profileProvider);
      if (profileAsync.isLoading) return null;

      final profile = profileAsync.value;
      if (profile == null) return path == '/login' ? null : '/login';

      // An invited person chooses a password before anything else.
      if (profile.mustSetPassword) return path == '/set-password' ? null : '/set-password';
      if (path == '/set-password') return ref.read(homeRouteProvider);

      // Pending, rejected or suspended: only the waiting screen.
      if (!profile.isActive) return path == '/pending' ? null : '/pending';
      if (path == '/pending') return ref.read(homeRouteProvider);

      // A student's first visit: the welcome screens and a short survey.
      if (profile.needsOnboarding) return path == '/welcome' ? null : '/welcome';
      if (path == '/welcome') return ref.read(homeRouteProvider);

      if (onAuthScreen) return ref.read(homeRouteProvider);

      // Keep people out of areas their role does not cover.
      if (path.startsWith('/admin') && profile.role != UserRole.admin) {
        return ref.read(homeRouteProvider);
      }
      if (path.startsWith('/staff') && !profile.role.isStaff) {
        return '/browse';
      }
      if (_studentOnly(path) && profile.role != UserRole.student) {
        return ref.read(homeRouteProvider);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify', builder: (_, __) => const VerifyEmailScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(path: '/set-password', builder: (_, __) => const SetPasswordScreen()),
      GoRoute(path: '/pending', builder: (_, __) => const PendingScreen()),

      ShellRoute(
        navigatorKey: shellKey,
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/browse', builder: (_, __) => const BrowseScreen()),
          GoRoute(path: '/borrowing', builder: (_, __) => const MyBorrowingScreen()),
          GoRoute(path: '/plan', builder: (_, __) => const PlanHomeScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/study', builder: (_, __) => const StudyHomeScreen()),
          GoRoute(path: '/staff/requests', builder: (_, __) => const RequestQueueScreen()),
          GoRoute(path: '/staff/library', builder: (_, __) => const LibraryScreen()),
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
          GoRoute(path: '/admin/users', builder: (_, __) => const UsersScreen()),
        ],
      ),

      GoRoute(path: '/updates', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/profile/edit', builder: (_, __) => const ProfileEditScreen()),
      GoRoute(path: '/admin/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(
        path: '/plan/:id',
        builder: (_, s) => PlanDetailScreen(planId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/resource/:id',
        builder: (_, s) => ResourceDetailScreen(resourceId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/resource/:id/borrow',
        builder: (_, s) => BorrowRequestScreen(resourceId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/staff/request/:id',
        builder: (_, s) => RequestDetailScreen(requestId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/staff/books/new', builder: (_, __) => const BookFormScreen()),
      GoRoute(
        path: '/staff/books/:id/edit',
        builder: (_, s) => BookFormScreen(bookId: s.pathParameters['id']),
      ),
      GoRoute(path: '/staff/books/import', builder: (_, __) => const BookImportScreen()),
      GoRoute(path: '/staff/papers/upload', builder: (_, __) => const PaperUploadScreen()),
      GoRoute(
        path: '/staff/papers/:id/edit',
        builder: (_, s) => PaperFormScreen(paperId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/staff/links/new', builder: (_, __) => const LinkFormScreen()),
      GoRoute(
        path: '/staff/links/:id/edit',
        builder: (_, s) => LinkFormScreen(linkId: s.pathParameters['id']),
      ),
      GoRoute(path: '/admin/users/new', builder: (_, __) => const CreateAccountScreen()),

      // Study assistant screens open full screen, above the tab bar.
      GoRoute(path: '/study/note/new', builder: (_, __) => const NoteEditorScreen()),
      // A study kit. ?build=1 starts building it with AI; ?tab=0..4 opens
      // one of its parts.
      GoRoute(
        path: '/study/note/:id',
        builder: (_, s) => KitScreen(
          noteId: s.pathParameters['id']!,
          initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
          autoBuild: s.uri.queryParameters['build'] == '1',
        ),
      ),
      GoRoute(
        path: '/study/test/:id',
        builder: (_, s) => TestTakeScreen(testId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/study/deck/:id/game/:game',
        builder: (_, s) => KitGameScreen(
          deckId: s.pathParameters['id']!,
          game: GameKindX.parse(s.pathParameters['game']) ?? GameKind.matching,
        ),
      ),
      GoRoute(
        path: '/study/note/:id/edit',
        builder: (_, s) => NoteEditorScreen(noteId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/study/deck/:id',
        builder: (_, s) => DeckScreen(deckId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/study/deck/:id/study',
        builder: (_, s) => DeckStudyScreen(deckId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/study/quiz/:id',
        builder: (_, s) => QuizScreen(quizId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/study/quiz/:id/take',
        builder: (_, s) => QuizTakeScreen(quizId: s.pathParameters['id']!),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('No screen at ${state.uri.path}')),
    ),
  );
});

class _Refresh extends ChangeNotifier {
  _Refresh(Ref ref) {
    ref.listen(authStateProvider, (_, next) {
      if (next.value?.event == AuthChangeEvent.passwordRecovery) {
        ref.read(passwordRecoveryProvider.notifier).state = true;
      }
      notifyListeners();
    });
    ref.listen(passwordRecoveryProvider, (_, __) => notifyListeners());
    ref.listen(profileProvider, (_, __) => notifyListeners());
  }
}
