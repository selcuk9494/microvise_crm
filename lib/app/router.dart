import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_providers.dart';
import '../core/routing/go_router_refresh_stream.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/auth/login_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/service/service_screen.dart';
import '../features/setup/setup_required_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/work_orders/work_orders_kanban_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final session = ref.watch(sessionProvider);

  final refreshListenable = client == null
      ? null
      : GoRouterRefreshStream(client.auth.onAuthStateChange);

  ref.onDispose(() => refreshListenable?.dispose());

  final routes = <RouteBase>[
    GoRoute(
      path: '/kurulum',
      builder: (context, state) => const SetupRequiredScreen(),
    ),
    GoRoute(
      path: '/giris',
      builder: (context, state) => const LoginScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          redirect: (_, __) => '/panel',
        ),
        GoRoute(
          path: '/panel',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/musteriler',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: CustomersScreen(),
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => CustomerDetailScreen(
                customerId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/is-emirleri',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WorkOrdersKanbanScreen(),
          ),
        ),
        GoRoute(
          path: '/servis',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ServiceScreen(),
          ),
        ),
        GoRoute(
          path: '/raporlar',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ReportsScreen(),
          ),
        ),
      ],
    ),
  ];

  final goRouter = GoRouter(
    routes: routes,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isConfigured = client != null;
      final isSetup = state.matchedLocation == '/kurulum';
      if (!isConfigured) return isSetup ? null : '/kurulum';

      final isLoggingIn = state.matchedLocation == '/giris';
      final isLoggedIn = session != null;

      if (!isLoggedIn) return isLoggingIn ? null : '/giris';
      if (isLoggingIn || isSetup) return '/panel';

      return null;
    },
  );

  ref.watch(authStateProvider);
  return goRouter;
});
