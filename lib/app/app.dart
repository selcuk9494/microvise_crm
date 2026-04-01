import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_providers.dart';
import '../features/dashboard/dashboard_providers.dart';
import '../features/work_orders/work_orders_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  String? _prefetchedToken;

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(accessTokenProvider, (prev, next) {
      final token = next?.trim();
      if (token == null || token.isEmpty) return;
      if (_prefetchedToken == token) return;
      _prefetchedToken = token;
      Future.microtask(() {
        ref.read(dashboardMetricsProvider.future);
        ref.read(workOrdersBoardProvider.future);
      });
    });

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Microvise CRM',
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
