import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_providers.dart';
import '../features/dashboard/dashboard_providers.dart';
import '../features/work_orders/work_orders_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_provider.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  String? _prefetchedToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncAppThemeBrightness();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _syncAppThemeBrightness();
    setState(() {});
  }

  void _syncAppThemeBrightness() {
    final mode = ref.read(themeModeProvider);
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final brightness = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platform,
    };
    AppTheme.applyBrightness(brightness);
  }

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

    final themeMode = ref.watch(themeModeProvider);
    _syncAppThemeBrightness();

    final router = ref.watch(appRouterProvider);

    // `AppTheme`'in renk getter'ları (`AppTheme.text`, `.surface`, ...)
    // Theme.of(context)'e değil statik bir `_brightness` alanına bağlı.
    // Bu yüzden tema modu değiştiğinde yalnızca bu widget (App) yeniden
    // çiziliyordu; ekrandaki mevcut sayfa widget'ları (route içeriği) tekrar
    // build edilmediği için eski renklerde kalıyordu — kullanıcı ancak
    // çıkış yapıp tekrar girdiğinde (yani sayfa widget'ları GoRouter
    // tarafından sıfırdan oluşturulduğunda) yeni temayı görüyordu.
    //
    // Düzeltme: MaterialApp.router'ı çözümlenmiş parlaklığa göre keyliyoruz.
    // Tema değiştiğinde Flutter bu widget'ı (ve altındaki mevcut route
    // içeriğini) sıfırdan kurar; GoRouter örneği (appRouterProvider) ve tüm
    // Riverpod durumu/iş mantığı aynı kalır, yalnızca geçerli sayfa yeniden
    // build edilip güncel AppTheme renklerini okur. Aktif konum GoRouter'ın
    // kendi dahili durumunda tutulduğu için korunur.
    return MaterialApp.router(
      key: ValueKey(AppTheme.brightness),
      debugShowCheckedModeBanner: false,
      title: 'Microvise CRM',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
