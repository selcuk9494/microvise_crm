import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/app_config.dart';
import '../core/auth/auth_providers.dart';
import '../core/routing/go_router_refresh_stream.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/auth/login_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/billing/billing_screen.dart';
import '../features/products/products_screen.dart';
import '../features/definitions/definitions_screen.dart';
import '../features/forms/forms_screen.dart';
import '../features/application_forms/application_form_screen.dart';
import '../features/forms/scrap_form_screen.dart';
import '../features/forms/transfer_form_screen.dart';
import '../features/personnel/personnel_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/service/service_screen.dart';
import '../features/service/service_detail_screen.dart';
import '../features/setup/setup_required_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/work_orders/work_orders_kanban_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final accessToken = ref.watch(accessTokenProvider);

  final GoRouterRefreshStream? supabaseRefresh = client == null
      ? null
      : GoRouterRefreshStream(client.auth.onAuthStateChange);

  final apiAuthRefresh = ValueNotifier<int>(0);
  ref.listen<String?>(apiAccessTokenProvider, (previous, next) {
    if (previous != next) apiAuthRefresh.value++;
  });

  final mergedRefresh = Listenable.merge(
    [apiAuthRefresh, supabaseRefresh]
        .whereType<Listenable>()
        .toList(growable: false),
  );

  ref.onDispose(() => supabaseRefresh?.dispose());
  ref.onDispose(apiAuthRefresh.dispose);

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
          redirect: (_, _) => '/panel',
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
          path: '/formlar',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: FormsScreen(),
          ),
          routes: [
            GoRoute(
              path: 'basvuru',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ApplicationFormScreen(),
              ),
            ),
            GoRoute(
              path: 'hurda',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ScrapFormScreen(),
              ),
            ),
            GoRoute(
              path: 'devir',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: TransferFormScreen(),
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
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => ServiceDetailScreen(
                serviceId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/raporlar',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ReportsScreen(),
          ),
        ),
        GoRoute(
          path: '/personel',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PersonnelScreen(),
          ),
        ),
        GoRoute(
          path: '/faturalama',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: BillingScreen(),
          ),
        ),
        GoRoute(
          path: '/urunler',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProductsScreen(),
          ),
        ),
        GoRoute(
          path: '/tanimlamalar',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DefinitionsScreen(),
          ),
        ),
      ],
    ),
  ];

  final goRouter = GoRouter(
    routes: routes,
    refreshListenable: mergedRefresh,
    redirect: (context, state) {
      final isConfigured = AppConfig.apiBaseUrl != null || client != null;
      final isSetup = state.matchedLocation == '/kurulum';
      if (!isConfigured) return isSetup ? null : '/kurulum';

      final isLoggingIn = state.matchedLocation == '/giris';
      final isLoggedIn = accessToken != null;

      if (!isLoggedIn) return isLoggingIn ? null : '/giris';
      if (isLoggingIn || isSetup) return '/panel';

      return null;
    },
  );

  ref.watch(authStateProvider);
  return goRouter;
});
