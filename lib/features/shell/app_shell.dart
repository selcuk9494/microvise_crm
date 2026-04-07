import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_breakpoints.dart';
import '../../core/ui/app_card.dart';

class _FormsNavExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void set(bool value) => state = value;
}

final formsNavExpandedProvider =
    NotifierProvider<_FormsNavExpandedNotifier, bool>(
  _FormsNavExpandedNotifier.new,
);

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= AppBreakpoints.desktopMin;

    if (isDesktop) {
      return _DesktopShell(child: child);
    }

    return _MobileShell(child: child);
  }
}

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final allowedPages = ref.watch(currentUserPagePermissionsProvider);
    final items =
        _navItems.where((item) => allowedPages.contains(item.pageKey)).toList();
    final isFormsExpanded = ref.watch(formsNavExpandedProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          Container(
            width: 280,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    AppTheme.primary.withValues(alpha: 0.06),
                    AppTheme.surface,
                  ),
                  AppTheme.surface,
                  Color.alphaBlend(
                    AppTheme.accent.withValues(alpha: 0.06),
                    AppTheme.surface,
                  ),
                ],
              ),
              border: Border(
                right: BorderSide(color: AppTheme.border),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(6, 0),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _BrandHeader(onTap: () => context.go('/panel')),
                    const Gap(16),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final item in items) ...[
                            if (item.pageKey == 'formlar')
                              _FormsNavGroup(
                                label: item.label,
                                icon: item.icon,
                                active: _isActive(location, item.path),
                                accentColor: _navAccentColor(item.pageKey),
                                expanded: isFormsExpanded,
                                onHeaderTap: () {
                                  ref
                                      .read(formsNavExpandedProvider.notifier)
                                      .toggle();
                                  if (!isFormsExpanded) {
                                    context.go(item.path);
                                  }
                                },
                                subItems: [
                                  _FormsNavSubItem(
                                    label: 'Başvuru',
                                    path: '/formlar/basvuru',
                                  ),
                                  _FormsNavSubItem(
                                    label: 'Hurda',
                                    path: '/formlar/hurda',
                                  ),
                                  _FormsNavSubItem(
                                    label: 'Arıza',
                                    path: '/formlar/ariza',
                                  ),
                                  _FormsNavSubItem(
                                    label: 'Devir',
                                    path: '/formlar/devir',
                                  ),
                                  _FormsNavSubItem(
                                    label: 'Seri Takip',
                                    path: '/formlar/seri-takip',
                                  ),
                                ],
                                matchedLocation: location,
                              )
                            else
                              _SidebarItem(
                                label: item.label,
                                icon: item.icon,
                                active: _isActive(location, item.path),
                                accentColor: _navAccentColor(item.pageKey),
                                onTap: () => context.go(item.path),
                              ),
                            const Gap(10),
                          ],
                        ],
                      ),
                    ),
                    const Gap(12),
                    _AccountCard(
                      onSignOut: () async {
                        ref.read(apiAccessTokenProvider.notifier).clear();
                        final client = ref.read(supabaseClientProvider);
                        await client?.auth.signOut();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShell extends ConsumerWidget {
  const _MobileShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final allowedPages = ref.watch(currentUserPagePermissionsProvider);

    final items = <_NavItem>[
      _navItems.firstWhere((e) => e.path == '/panel'),
      if (allowedPages.contains('musteriler'))
        _navItems.firstWhere((e) => e.path == '/musteriler'),
      if (allowedPages.contains('formlar'))
        _navItems.firstWhere((e) => e.path == '/formlar'),
      if (allowedPages.contains('is_emirleri'))
        _navItems.firstWhere((e) => e.path == '/is-emirleri'),
    ];

    int currentIndexForLocation() {
      for (var i = 0; i < items.length; i++) {
        if (_isActive(location, items[i].path)) return i;
      }
      return 0;
    }

    final currentIndex = currentIndexForLocation();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: child,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () => _showQuickCreateSheet(context),
        child: const Icon(Icons.add_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        height: 66,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            const Gap(8),
            if (items.isNotEmpty)
              _BottomItem(
                label: items[0].label,
                icon: items[0].icon,
                active: currentIndex == 0,
                onTap: () => context.go(items[0].path),
              ),
            if (items.length > 1)
              _BottomItem(
                label: items[1].label,
                icon: items[1].icon,
                active: currentIndex == 1,
                onTap: () => context.go(items[1].path),
              ),
            const Spacer(),
            if (items.length > 2)
              _BottomItem(
                label: items[2].label,
                icon: items[2].icon,
                active: currentIndex == 2,
                onTap: () => context.go(items[2].path),
              ),
            if (items.length > 3)
              _BottomItem(
                label: items[3].label,
                icon: items[3].icon,
                active: currentIndex == 3,
                onTap: () => context.go(items[3].path),
              ),
            _BottomItem(
              label: 'Hesap',
              icon: Icons.person_rounded,
              active: false,
              onTap: () => _showMobileAccountSheet(context, ref),
            ),
            const Gap(8),
          ],
        ),
      ),
    );
  }
}

Future<void> _showMobileAccountSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Consumer(
        builder: (context, ref, _) {
          final profile = ref.watch(currentUserProfileProvider).value;
          final name = (profile?.fullName ?? '').trim();
          final role = (profile?.role ?? 'personel').trim();

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hesap', style: Theme.of(context).textTheme.titleMedium),
              const Gap(12),
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppTheme.primary,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name.isEmpty ? 'Kullanıcı' : name,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          Text(
                            role == 'admin' ? 'Admin' : 'Personel',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              FilledButton.tonalIcon(
                onPressed: () async {
                  ref.read(apiAccessTokenProvider.notifier).clear(persist: true);
                  final client = ref.read(supabaseClientProvider);
                  await client?.auth.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  context.go('/login');
                },
                icon: Icon(
                  PhosphorIcons.signOut(PhosphorIconsStyle.regular),
                  size: 18,
                ),
                label: const Text('Çıkış Yap'),
              ),
              const Gap(8),
            ],
          );
        },
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).cardTheme.color ?? AppTheme.surface;
    final bgTop =
        Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.12), surface);
    final bgBottom =
        Color.alphaBlend(AppTheme.accent.withValues(alpha: 0.08), surface);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgTop, bgBottom],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primary, AppTheme.primaryDeep],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const Gap(12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Microvise',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  'CRM & Servis',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppTheme.background,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            const Spacer(),
            IconButton(
              tooltip: 'Bildirimler',
              onPressed: () {},
              icon: Icon(
                PhosphorIcons.bell(PhosphorIconsStyle.regular),
                color: const Color(0xFF0F172A),
              ),
            ),
            const Gap(6),
            _ProfileButton(),
          ],
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ),
              const Gap(10),
              Text(
                'Profil',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Gap(6),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: () {},
          child: const Text('Ayarlar'),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? Color.alphaBlend(
                  accentColor.withValues(alpha: 0.16),
                  AppTheme.surfaceMuted,
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? accentColor.withValues(alpha: 0.32)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: active
                    ? accentColor.withValues(alpha: 0.16)
                    : accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active
                      ? accentColor.withValues(alpha: 0.30)
                      : accentColor.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: active ? accentColor : accentColor.withValues(alpha: 0.92),
              ),
            ),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? accentColor : const Color(0xFF0F172A),
                    ),
              ),
            ),
            if (active)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FormsNavSubItem {
  const _FormsNavSubItem({required this.label, required this.path});

  final String label;
  final String path;
}

class _FormsNavGroup extends StatelessWidget {
  const _FormsNavGroup({
    required this.label,
    required this.icon,
    required this.active,
    required this.accentColor,
    required this.expanded,
    required this.onHeaderTap,
    required this.subItems,
    required this.matchedLocation,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color accentColor;
  final bool expanded;
  final VoidCallback onHeaderTap;
  final List<_FormsNavSubItem> subItems;
  final String matchedLocation;

  @override
  Widget build(BuildContext context) {
    final anySubActive = subItems.any((e) => _isActive(matchedLocation, e.path));
    final isActive = active || anySubActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onHeaderTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? Color.alphaBlend(
                      accentColor.withValues(alpha: 0.16),
                      AppTheme.surfaceMuted,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? accentColor.withValues(alpha: 0.32)
                    : AppTheme.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isActive
                        ? accentColor.withValues(alpha: 0.16)
                        : accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? accentColor.withValues(alpha: 0.30)
                          : accentColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isActive
                        ? accentColor
                        : accentColor.withValues(alpha: 0.92),
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive ? accentColor : const Color(0xFF0F172A),
                        ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: (isActive ? accentColor : const Color(0xFF64748B))
                      .withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accentColor.withValues(alpha: 0.06),
                  AppTheme.surfaceMuted,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? accentColor.withValues(alpha: 0.18)
                      : AppTheme.border,
                ),
              ),
              child: Column(
                children: [
                  for (final item in subItems) ...[
                    _SidebarSubItem(
                      label: item.label,
                      active: _isActive(matchedLocation, item.path),
                      accentColor: accentColor,
                      onTap: () => context.go(item.path),
                    ),
                    if (item != subItems.last) const Gap(6),
                  ],
                ],
              ),
            ),
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}

class _SidebarSubItem extends StatelessWidget {
  const _SidebarSubItem({
    required this.label,
    required this.active,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? accentColor : const Color(0xFF334155);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 40,
        margin: const EdgeInsets.only(left: 22),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? accentColor.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? accentColor.withValues(alpha: 0.20)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.primary : const Color(0xFF64748B);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const Gap(4),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).cardTheme.color ?? AppTheme.surface;
    final bgTop =
        Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.12), surface);
    final bgBottom =
        Color.alphaBlend(AppTheme.accent.withValues(alpha: 0.08), surface);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgTop, bgBottom],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            child: const Icon(Icons.person_rounded, color: AppTheme.primary),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hesap',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  'Admin / Personel',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Çıkış Yap',
            onPressed: onSignOut,
            icon: Icon(
              PhosphorIcons.signOut(PhosphorIconsStyle.regular),
              size: 18,
              color: const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

Color _navAccentColor(String pageKey) {
  switch (pageKey) {
    case 'panel':
      return AppTheme.primary;
    case 'musteriler':
      return AppTheme.accent;
    case 'formlar':
      return AppTheme.warning;
    case 'is_emirleri':
      return const Color(0xFF16A34A);
    case 'servis':
      return const Color(0xFF0EA5E9);
    case 'raporlar':
      return const Color(0xFF7C3AED);
    case 'urunler':
      return const Color(0xFF2563EB);
    case 'faturalama':
      return const Color(0xFFF97316);
    case 'tanimlamalar':
      return const Color(0xFF334155);
    case 'personel':
      return const Color(0xFFDB2777);
    default:
      return AppTheme.primary;
  }
}

Future<void> _showQuickCreateSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hızlı Ekle', style: Theme.of(context).textTheme.titleMedium),
          const Gap(10),
          _SheetItem(
            title: 'Yeni Müşteri',
            icon: PhosphorIcons.userPlus(PhosphorIconsStyle.regular),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/musteriler?yeni=1');
            },
          ),
          _SheetItem(
            title: 'Yeni İş Emri',
            icon: PhosphorIcons.clipboardText(PhosphorIconsStyle.regular),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/is-emirleri?yeni=1');
            },
          ),
          _SheetItem(
            title: 'Yeni Servis Kaydı',
            icon: PhosphorIcons.wrench(PhosphorIconsStyle.regular),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/servis?yeni=1');
            },
          ),
          const Gap(6),
        ],
      ),
    ),
  );
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({required this.title, required this.icon, required this.onTap});

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 18),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

bool _isActive(String matchedLocation, String path) {
  if (path == '/panel') return matchedLocation == '/panel' || matchedLocation == '/';
  return matchedLocation == path || matchedLocation.startsWith('$path/');
}

class _NavItem {
  const _NavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.pageKey,
  });

  final String path;
  final String label;
  final IconData icon;
  final String pageKey;
}

final _navItems = <_NavItem>[
  _NavItem(
    path: '/panel',
    label: 'Panel',
    icon: PhosphorIcons.house(PhosphorIconsStyle.regular),
    pageKey: 'panel',
  ),
  _NavItem(
    path: '/musteriler',
    label: 'Müşteriler',
    icon: PhosphorIcons.users(PhosphorIconsStyle.regular),
    pageKey: 'musteriler',
  ),
  _NavItem(
    path: '/formlar',
    label: 'Formlar',
    icon: PhosphorIcons.fileText(PhosphorIconsStyle.regular),
    pageKey: 'formlar',
  ),
  _NavItem(
    path: '/is-emirleri',
    label: 'İş Emirleri',
    icon: PhosphorIcons.kanban(PhosphorIconsStyle.regular),
    pageKey: 'is_emirleri',
  ),
  _NavItem(
    path: '/servis',
    label: 'Servis',
    icon: PhosphorIcons.wrench(PhosphorIconsStyle.regular),
    pageKey: 'servis',
  ),
  _NavItem(
    path: '/raporlar',
    label: 'Raporlar',
    icon: PhosphorIcons.chartBar(PhosphorIconsStyle.regular),
    pageKey: 'raporlar',
  ),
  _NavItem(
    path: '/urunler',
    label: 'Hat & Lisans',
    icon: PhosphorIcons.simCard(PhosphorIconsStyle.regular),
    pageKey: 'urunler',
  ),
  _NavItem(
    path: '/faturalama',
    label: 'Faturalama',
    icon: PhosphorIcons.receipt(PhosphorIconsStyle.regular),
    pageKey: 'faturalama',
  ),
  _NavItem(
    path: '/tanimlamalar',
    label: 'Tanımlamalar',
    icon: PhosphorIcons.sliders(PhosphorIconsStyle.regular),
    pageKey: 'tanimlamalar',
  ),
  _NavItem(
    path: '/personel',
    label: 'Personel',
    icon: PhosphorIcons.identificationCard(PhosphorIconsStyle.regular),
    pageKey: 'personel',
  ),
];
