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

class _DesktopShell extends ConsumerStatefulWidget {
  const _DesktopShell({required this.child});

  final Widget child;

  @override
  ConsumerState<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<_DesktopShell> {
  bool _formsExpanded = false;
  bool _billingExpanded = false;

  Future<void> _signOut() async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client?.auth.signOut();
      ref.invalidate(authStateProvider);
      ref.invalidate(sessionChangesProvider);
      ref.invalidate(currentUserProfileProvider);
      if (!mounted) return;
      context.go('/giris');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Çıkış yapılamadı: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final allowedPages = ref.watch(currentUserPagePermissionsProvider);
    final items = _navItems
        .where((item) => allowedPages.contains(item.permissionKey))
        .map(
          (item) => item.copyWith(
            children: item.children
                .where(
                  (child) =>
                      allowedPages.contains(child.permissionKey) ||
                      item.permissionKey == child.permissionKey,
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    final hasActiveFormsChild = items
        .where((item) => item.path == '/formlar')
        .expand((item) => item.children)
        .any((child) => _isActive(location, child.path));
    final hasActiveBillingChild = items
        .where((item) => item.path == '/faturalama')
        .expand((item) => item.children)
        .any((child) => _isActive(location, child.path));

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          Container(
            width: 236,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: AppTheme.border)),
              boxShadow: AppTheme.cardShadow,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  children: [
                    _BrandHeader(onTap: () => context.go('/panel')),
                    const Gap(10),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final item in items) ...[
                            if (item.children.isEmpty)
                              _SidebarItem(
                                label: item.label,
                                icon: item.icon,
                                active: _isActive(location, item.path),
                                onTap: () => context.go(item.path),
                              )
                            else if (item.path == '/formlar')
                              _SidebarExpandableItem(
                                label: item.label,
                                icon: item.icon,
                                active:
                                    _isActive(location, item.path) ||
                                    hasActiveFormsChild,
                                expanded: _formsExpanded || hasActiveFormsChild,
                                onTap: () {
                                  setState(() {
                                    _formsExpanded = !_formsExpanded;
                                  });
                                },
                              )
                            else
                              _SidebarExpandableItem(
                                label: item.label,
                                icon: item.icon,
                                active:
                                    _isActive(location, item.path) ||
                                    hasActiveBillingChild,
                                expanded: _billingExpanded || hasActiveBillingChild,
                                onTap: () {
                                  setState(() {
                                    _billingExpanded = !_billingExpanded;
                                  });
                                },
                              ),
                            if (item.children.isNotEmpty &&
                                (((item.path == '/formlar') &&
                                        (_formsExpanded || hasActiveFormsChild)) ||
                                    ((item.path == '/faturalama') &&
                                        (_billingExpanded || hasActiveBillingChild)))) ...[
                              const Gap(6),
                              Padding(
                                padding: const EdgeInsets.only(left: 20),
                                child: Column(
                                  children: [
                                    for (final child in item.children) ...[
                                      _SidebarSubItem(
                                        label: child.label,
                                        active: _isActive(location, child.path),
                                        onTap: () => context.go(child.path),
                                      ),
                                      const Gap(6),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const Gap(6),
                          ],
                        ],
                      ),
                    ),
                    const Gap(12),
                    _AccountCard(
                      onSignOut: _signOut,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(onSearchTap: () => _showSearchSheet(context)),
                Expanded(child: widget.child),
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
    final mobileItems = _mobileItems
        .where((item) => allowedPages.contains(item.permissionKey))
        .toList(growable: false);
    final currentIndex = _mobileIndexForLocation(location, mobileItems);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: child,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        onPressed: () => _showQuickCreateSheet(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        height: 74,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            const Gap(8),
            for (var i = 0; i < mobileItems.length; i++) ...[
              if (i == 2) const Spacer(),
              _BottomItem(
                label: mobileItems[i].label,
                icon: mobileItems[i].icon,
                active: currentIndex == i,
                onTap: () => context.go(mobileItems[i].path),
              ),
            ],
            const Spacer(),
            const Gap(8),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                boxShadow: AppTheme.cardShadow,
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const Gap(10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Microvise',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'CRM & Servis',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
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
  const _TopBar({required this.onSearchTap});

  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onSearchTap,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIcons.magnifyingGlass(
                          PhosphorIconsStyle.regular,
                        ),
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      const Gap(10),
                      Text(
                        'Ara (müşteri, iş emri, servis...)',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF8CA0B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(12),
            IconButton(
              tooltip: 'Bildirimler',
              onPressed: () {},
              icon: Icon(
                PhosphorIcons.bell(PhosphorIconsStyle.regular),
                color: AppTheme.text,
              ),
            ),
            const Gap(10),
            _ProfileButton(),
          ],
        ),
      ),
    );
  }
}

class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final displayName = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim()
        : 'Profil';
    final roleName = profile?.role == 'admin' ? 'Admin' : 'Personel';
    final client = ref.read(supabaseClientProvider);

    Future<void> signOut() async {
      try {
        await client?.auth.signOut();
        ref.invalidate(authStateProvider);
        ref.invalidate(sessionChangesProvider);
        ref.invalidate(currentUserProfileProvider);
        if (!context.mounted) return;
        context.go('/giris');
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Çıkış yapılamadı: $e')));
      }
    }

    return MenuAnchor(
      builder: (context, controller, child) => InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: AppTheme.primary,
                ),
              ),
              const Gap(8),
              Text(
                displayName,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const Gap(6),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: null,
          leadingIcon: const Icon(Icons.shield_outlined, size: 18),
          child: Text(roleName),
        ),
        MenuItemButton(
          onPressed: signOut,
          leadingIcon: const Icon(Icons.logout_rounded, size: 18),
          child: const Text('Çıkış Yap'),
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
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? AppTheme.primarySoft.withValues(alpha: 0.85)
        : Colors.transparent;
    final border = active ? Colors.transparent : Colors.transparent;
    final fg = active ? AppTheme.primaryDark : AppTheme.text;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

class _SidebarExpandableItem extends StatelessWidget {
  const _SidebarExpandableItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? AppTheme.primarySoft.withValues(alpha: 0.85)
        : Colors.transparent;
    final border = Colors.transparent;
    final fg = active ? AppTheme.primaryDark : AppTheme.text;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
              color: fg,
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
    final color = active ? AppTheme.primaryDark : AppTheme.textMuted;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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

class _SidebarSubItem extends StatelessWidget {
  const _SidebarSubItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppTheme.primaryDark : AppTheme.textMuted;
    final bg = active
        ? AppTheme.primarySoft.withValues(alpha: 0.72)
        : Colors.transparent;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? AppTheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
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
    return Consumer(
      builder: (context, ref, _) {
        final profile = ref.watch(currentUserProfileProvider).value;
        final displayName = profile?.fullName?.trim().isNotEmpty == true
            ? profile!.fullName!.trim()
            : 'Hesap';
        final roleName = profile?.role == 'admin' ? 'Admin' : 'Personel';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
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
                      displayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      roleName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
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
                  color: AppTheme.text,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _showQuickCreateSheet(BuildContext context, WidgetRef ref) async {
  final allowedPages = ref.read(currentUserPagePermissionsProvider);
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
          if (allowedPages.contains(kPageCustomers))
            _SheetItem(
              title: 'Yeni Müşteri',
              icon: PhosphorIcons.userPlus(PhosphorIconsStyle.regular),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/musteriler?yeni=1');
              },
            ),
          if (allowedPages.contains(kPageWorkOrders))
            _SheetItem(
              title: 'Yeni İş Emri',
              icon: PhosphorIcons.clipboardText(PhosphorIconsStyle.regular),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/is-emirleri?yeni=1');
              },
            ),
          if (allowedPages.contains(kPageService))
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

Future<void> _showSearchSheet(BuildContext context) async {
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
          Text('Arama', style: Theme.of(context).textTheme.titleMedium),
          const Gap(10),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Ara',
              hintText: 'Müşteri adı, iş emri no, servis...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const Gap(12),
          Text(
            'Son aramalar yakında burada görünecek.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
          const Gap(12),
        ],
      ),
    ),
  );
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });

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
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

bool _isActive(String matchedLocation, String path) {
  if (path == '/panel') {
    return matchedLocation == '/panel' || matchedLocation == '/';
  }
  return matchedLocation == path || matchedLocation.startsWith('$path/');
}

int _mobileIndexForLocation(String matchedLocation, List<_NavItem> items) {
  for (var i = 0; i < items.length; i++) {
    if (_isActive(matchedLocation, items[i].path)) return i;
  }
  return 0;
}

class _NavItem {
  const _NavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.permissionKey,
    this.children = const [],
  });

  final String path;
  final String label;
  final IconData icon;
  final String permissionKey;
  final List<_NavSubItem> children;

  _NavItem copyWith({List<_NavSubItem>? children}) {
    return _NavItem(
      path: path,
      label: label,
      icon: icon,
      permissionKey: permissionKey,
      children: children ?? this.children,
    );
  }
}

class _NavSubItem {
  const _NavSubItem({
    required this.path,
    required this.label,
    required this.permissionKey,
  });

  final String path;
  final String label;
  final String permissionKey;
}

final _navItems = <_NavItem>[
  _NavItem(
    path: '/panel',
    label: 'Panel',
    icon: PhosphorIcons.house(PhosphorIconsStyle.regular),
    permissionKey: kPagePanel,
  ),
  _NavItem(
    path: '/musteriler',
    label: 'Müşteriler',
    icon: PhosphorIcons.users(PhosphorIconsStyle.regular),
    permissionKey: kPageCustomers,
  ),
  _NavItem(
    path: '/formlar',
    label: 'Formlar',
    icon: PhosphorIcons.files(PhosphorIconsStyle.regular),
    permissionKey: kPageForms,
    children: const [
      _NavSubItem(
        path: '/formlar/basvuru',
        label: 'Başvuru Formu',
        permissionKey: kPageForms,
      ),
      _NavSubItem(
        path: '/formlar/hurda',
        label: 'Hurda Formu',
        permissionKey: kPageForms,
      ),
      _NavSubItem(
        path: '/formlar/devir',
        label: 'Devir Formu',
        permissionKey: kPageForms,
      ),
    ],
  ),
  _NavItem(
    path: '/is-emirleri',
    label: 'İş Emirleri',
    icon: PhosphorIcons.kanban(PhosphorIconsStyle.regular),
    permissionKey: kPageWorkOrders,
  ),
  _NavItem(
    path: '/servis',
    label: 'Servis',
    icon: PhosphorIcons.wrench(PhosphorIconsStyle.regular),
    permissionKey: kPageService,
  ),
  _NavItem(
    path: '/raporlar',
    label: 'Raporlar',
    icon: PhosphorIcons.chartBar(PhosphorIconsStyle.regular),
    permissionKey: kPageReports,
  ),
  _NavItem(
    path: '/urunler',
    label: 'Hat & Lisans',
    icon: PhosphorIcons.simCard(PhosphorIconsStyle.regular),
    permissionKey: kPageProducts,
  ),
  _NavItem(
    path: '/faturalama',
    label: 'Faturalama',
    icon: PhosphorIcons.receipt(PhosphorIconsStyle.regular),
    permissionKey: kPageBilling,
    children: const [
      _NavSubItem(
        path: '/faturalama',
        label: 'Fatura Kuyruğu',
        permissionKey: kPageBilling,
      ),
      _NavSubItem(
        path: '/faturalama/faturalar',
        label: 'Faturalar',
        permissionKey: kPageBilling,
      ),
      _NavSubItem(
        path: '/faturalama/cari-hesaplar',
        label: 'Cari Hesaplar',
        permissionKey: kPageBilling,
      ),
      _NavSubItem(
        path: '/faturalama/stok',
        label: 'Stok',
        permissionKey: kPageBilling,
      ),
    ],
  ),
  _NavItem(
    path: '/tanimlamalar',
    label: 'Tanımlamalar',
    icon: PhosphorIcons.sliders(PhosphorIconsStyle.regular),
    permissionKey: kPageDefinitions,
  ),
  _NavItem(
    path: '/personel',
    label: 'Personel',
    icon: PhosphorIcons.identificationCard(PhosphorIconsStyle.regular),
    permissionKey: kPagePersonnel,
  ),
];

final _mobileItems = <_NavItem>[
  _navItems[0],
  _navItems[1],
  _navItems[3],
  _navItems[5],
];
