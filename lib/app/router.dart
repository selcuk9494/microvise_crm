import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_providers.dart';
import '../core/auth/feature_access_gate.dart';
import '../core/auth/user_profile_provider.dart';
import '../core/routing/go_router_refresh_stream.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/auth/login_screen.dart';
import '../features/application_forms/application_form_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/billing/billing_screen.dart';
import '../features/products/products_screen.dart';
import '../features/definitions/definitions_screen.dart';
import '../features/forms/forms_screen.dart';
import '../features/forms/scrap_form_screen.dart';
import '../features/forms/transfer_form_screen.dart';
import '../features/invoices/accounts_screen.dart';
import '../features/invoices/invoices_screen.dart';
import '../features/personnel/personnel_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/service/service_screen.dart';
import '../features/service/service_detail_screen.dart';
import '../features/setup/setup_required_screen.dart';
import '../features/stock/stock_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/work_orders/work_orders_kanban_screen.dart';
import '../features/work_orders/work_orders_list_screen.dart';

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
    GoRoute(path: '/giris', builder: (context, state) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', redirect: (context, state) => '/panel'),
        GoRoute(
          path: '/panel',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPagePanel,
                  child: DashboardScreen(),
                ),
              ),
        ),
        GoRoute(
          path: '/musteriler',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPageCustomers,
                  child: CustomersScreen(),
                ),
              ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  FeatureAccessGate(
                    pageKey: kPageCustomers,
                    child: CustomerDetailScreen(
                      customerId: state.pathParameters['id']!,
                    ),
                  ),
            ),
          ],
        ),
        GoRoute(
          path: '/formlar',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPageForms,
                  child: FormsScreen(),
                ),
              ),
          routes: [
            GoRoute(
              path: 'basvuru',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(
                    child: FeatureAccessGate(
                      pageKey: kPageForms,
                      child: ApplicationFormScreen(),
                    ),
                  ),
            ),
            GoRoute(
              path: 'hurda',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(
                    child: FeatureAccessGate(
                      pageKey: kPageForms,
                      child: ScrapFormScreen(),
                    ),
                  ),
            ),
            GoRoute(
              path: 'devir',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(
                    child: FeatureAccessGate(
                      pageKey: kPageForms,
                      child: TransferFormScreen(),
                    ),
                  ),
            ),
          ],
        ),
        GoRoute(
          path: '/is-emirleri',
          pageBuilder: (context, state) {
            final width = MediaQuery.sizeOf(context).width;
            final isMobileLayout = width < 860;
            return NoTransitionPage(
              child: FeatureAccessGate(
                pageKey: kPageWorkOrders,
                child: isMobileLayout
                    ? const WorkOrdersListScreen()
                    : const WorkOrdersKanbanScreen(),
              ),
            );
          },
        ),
        GoRoute(
          path: '/servis',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPageService,
                  child: ServiceScreen(),
                ),
              ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  FeatureAccessGate(
                    pageKey: kPageService,
                    child: ServiceDetailScreen(
                      serviceId: state.pathParameters['id']!,
                    ),
                  ),
            ),
          ],
        ),
        GoRoute(
          path: '/raporlar',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPageReports,
                  child: ReportsScreen(),
                ),
              ),
        ),
        GoRoute(
          path: '/personel',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPagePersonnel,
                  child: PersonnelScreen(),
                ),
              ),
        ),
        GoRoute(
          path: '/faturalama',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPageBilling,
                  child: BillingScreen(),
                ),
              ),
          routes: [
            GoRoute(
              path: 'faturalar',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(
                    child: FeatureAccessGate(
                      pageKey: kPageBilling,
                      child: InvoicesScreen(),
                    ),
                  ),
            ),
            GoRoute(
              path: 'cari-hesaplar',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(
                    child: FeatureAccessGate(
                      pageKey: kPageBilling,
                      child: AccountsScreen(),
                    ),
                  ),
            ),
            GoRoute(
              path: 'stok',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(
                    child: FeatureAccessGate(
                      pageKey: kPageBilling,
                      child: StockScreen(),
                    ),
                  ),
            ),
          ],
        ),
        GoRoute(
          path: '/urunler',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPageProducts,
                  child: ProductsScreen(),
                ),
              ),
        ),
        GoRoute(
          path: '/tanimlamalar',
          pageBuilder: (context, state) =>
              const NoTransitionPage(
                child: FeatureAccessGate(
                  pageKey: kPageDefinitions,
                  child: DefinitionsScreen(),
                ),
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
