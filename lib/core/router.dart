import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../state/providers.dart';
import '../models/profile.dart';
import '../ui/screens/auth/forgot_password_screen.dart';
import '../ui/screens/auth/login_screen.dart';
import '../ui/screens/auth/register_screen.dart';
import '../ui/screens/auth/reset_password_screen.dart';
import '../ui/screens/auth/verify_email_screen.dart';
import '../ui/screens/admin/roll_screen.dart';
import '../ui/screens/admin/users_screen.dart';
import '../ui/screens/shared/preview_screen.dart';
import '../ui/screens/shared/profile_screen.dart';
import '../ui/screens/shared/splash_screen.dart';
import '../ui/screens/staff/request_detail_screen.dart';
import '../ui/screens/staff/request_queue_screen.dart';
import '../ui/screens/staff/resource_manager_screen.dart';
import '../ui/screens/staff/upload_resource_screen.dart';
import '../ui/screens/student/borrow_request_screen.dart';
import '../ui/screens/student/browse_screen.dart';
import '../ui/screens/student/my_borrowing_screen.dart';
import '../ui/screens/student/notifications_screen.dart';
import '../ui/screens/student/resource_detail_screen.dart';
import '../ui/widgets/shell.dart';
import 'supabase.dart';

/// One gate, three questions, asked in order on every navigation:
/// is anyone signed in, is the address verified, and does the account
/// carry a profile? Each failure lands somewhere different.
final routerProvider = Provider<GoRouter>((ref) {
  final shellKey = GlobalKey<NavigatorState>();

  return GoRouter(
    initialLocation: '/',
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

      if (path == '/' || path == '/_preview') return null;

      if (!signedIn) return onAuthScreen ? null : '/login';

      if (!isVerified) return path == '/verify' ? null : '/verify';

      final profileAsync = ref.read(profileProvider);
      if (profileAsync.isLoading) return null;

      final profile = profileAsync.value;
      if (profile == null) return path == '/login' ? null : '/login';

      if (onAuthScreen) return ref.read(homeRouteProvider);

      // Keep people out of areas their role does not cover.
      if (path.startsWith('/admin') && profile.role != UserRole.admin) {
        return ref.read(homeRouteProvider);
      }
      if (path.startsWith('/staff') && !profile.role.isStaff) {
        return '/browse';
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
      GoRoute(path: '/_preview', builder: (_, __) => const PreviewScreen()),

      ShellRoute(
        navigatorKey: shellKey,
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/browse', builder: (_, __) => const BrowseScreen()),
          GoRoute(path: '/borrowing', builder: (_, __) => const MyBorrowingScreen()),
          GoRoute(path: '/updates', builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/staff/requests', builder: (_, __) => const RequestQueueScreen()),
          GoRoute(path: '/staff/resources', builder: (_, __) => const ResourceManagerScreen()),
          GoRoute(path: '/admin/roll', builder: (_, __) => const RollScreen()),
          GoRoute(path: '/admin/users', builder: (_, __) => const UsersScreen()),
        ],
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
      GoRoute(path: '/staff/upload', builder: (_, __) => const UploadResourceScreen()),
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
