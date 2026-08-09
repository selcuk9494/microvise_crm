import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/theme_mode_provider.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_breakpoints.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_phosphor_icons.dart';

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

class _EInvoiceNavExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final eInvoiceNavExpandedProvider =
    NotifierProvider<_EInvoiceNavExpandedNotifier, bool>(
      _EInvoiceNavExpandedNotifier.new,
    );

class _FinanceNavExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final financeNavExpandedProvider =
    NotifierProvider<_FinanceNavExpandedNotifier, bool>(
      _FinanceNavExpandedNotifier.new,
    );

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    if (profileAsync.isLoading || profileAsync.value == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 640;

    if (isDesktop) {
      return _DesktopShell(
        compact: width < AppBreakpoints.desktopMin,
        child: child,
      );
    }

    return _MobileShell(child: child);
  }
}

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({required this.child, required this.compact});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final allowedPages = ref.watch(currentUserPagePermissionsProvider);
    final isBankUser =
        ref.watch(currentUserProfileProvider).value?.isBankLike ?? false;
    final items = _visibleNavItems(
      allowedPages: allowedPages,
      isBankUser: isBankUser,
    );
    final isFormsExpanded = ref.watch(formsNavExpandedProvider);
    final isEInvoiceExpanded = ref.watch(eInvoiceNavExpandedProvider);
    final isFinanceExpanded = ref.watch(financeNavExpandedProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: DecoratedBox(
        decoration: AppTheme.pageCanvas,
        child: Row(
          children: [
            Container(
              width: compact ? 78 : 248,
              decoration: BoxDecoration(
                color: AppTheme.sidebar,
                border: Border(
                  right: BorderSide(
                    color: AppTheme.border.withValues(alpha: 0.8),
                  ),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 8 : 12,
                    compact ? 10 : 14,
                    compact ? 8 : 12,
                    compact ? 10 : 12,
                  ),
                  child: Column(
                    children: [
                      if (compact)
                        _CompactBrandButton(
                          onTap: () => context.go(
                            isBankUser ? '/banka-panel' : '/panel',
                          ),
                        )
                      else
                        _BrandHeader(
                          subtitle: isBankUser ? 'WebCR' : 'SAP Business',
                          onTap: () => context.go(
                            isBankUser ? '/banka-panel' : '/panel',
                          ),
                        ),
                      const Gap(10),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final item in items) ...[
                              if (compact)
                                _SidebarIconItem(
                                  label: item.label,
                                  icon: item.icon,
                                  active: _isActive(location, item.path),
                                  accentColor: _navAccentColor(item.pageKey),
                                  onTap: () => context.go(item.path),
                                )
                              else if (item.path == '/formlar' && !isBankUser)
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
                                  subItems: _formsNavSubItems(isBankUser),
                                  matchedLocation: location,
                                )
                              else if (item.pageKey == 'e_fatura')
                                _FormsNavGroup(
                                  label: item.label,
                                  icon: item.icon,
                                  active: _isActive(location, item.path),
                                  accentColor: _navAccentColor(item.pageKey),
                                  expanded: isEInvoiceExpanded,
                                  onHeaderTap: () {
                                    ref
                                        .read(
                                          eInvoiceNavExpandedProvider.notifier,
                                        )
                                        .toggle();
                                    context.go(item.path);
                                  },
                                  subItems: const [
                                    _FormsNavSubItem(
                                      label: 'Alış Faturası',
                                      path: '/e-fatura/alis',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Satış Faturası',
                                      path: '/e-fatura/satis',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Stok/Hizmet',
                                      path: '/e-fatura/stok',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Cari',
                                      path: '/e-fatura/cari',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Ayarlar',
                                      path: '/e-fatura/ayarlar',
                                    ),
                                  ],
                                  matchedLocation: location,
                                )
                              else if (item.pageKey == 'finans')
                                _FormsNavGroup(
                                  label: item.label,
                                  icon: item.icon,
                                  active: _isActive(location, item.path),
                                  accentColor: _navAccentColor(item.pageKey),
                                  expanded: isFinanceExpanded,
                                  onHeaderTap: () {
                                    ref
                                        .read(
                                          financeNavExpandedProvider.notifier,
                                        )
                                        .toggle();
                                    context.go(item.path);
                                  },
                                  subItems: const [
                                    _FormsNavSubItem(
                                      label: 'CRM Finans',
                                      path: '/finans',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Bankalar / Hesaplar',
                                      path: '/finans/akinsoft/bankalar',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Kasa',
                                      path: '/finans/akinsoft/kasa',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Transferler',
                                      path: '/finans/akinsoft/transferler',
                                    ),
                                    _FormsNavSubItem(
                                      label: 'Masraf Faturaları',
                                      path: '/finans/akinsoft/masraf',
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
                              const Gap(4),
                            ],
                          ],
                        ),
                      ),
                      const Gap(10),
                      compact
                          ? _CompactAccountButton(
                              onTap: () =>
                                  _showMobileAccountSheet(context, ref),
                            )
                          : _AccountCard(
                              profile: ref
                                  .watch(currentUserProfileProvider)
                                  .value,
                              onSignOut: () async {
                                ref
                                    .read(apiAccessTokenProvider.notifier)
                                    .clear();
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
                  Expanded(
                    child: ClipRect(child: SelectionArea(child: child)),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final isBankUser =
        ref.watch(currentUserProfileProvider).value?.isBankLike ?? false;
    final allowedItems = _visibleNavItems(
      allowedPages: allowedPages,
      isBankUser: isBankUser,
    );
    final pinnedItems = _mobilePinnedItems(allowedItems);
    final overflowActive = allowedItems.any(
      (item) =>
          _isActive(location, item.path) &&
          !pinnedItems.any((pinned) => pinned.path == item.path),
    );

    bool isPinnedActive(int index) {
      if (index >= pinnedItems.length) return false;
      return _isActive(location, pinnedItems[index].path);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: DecoratedBox(
        decoration: AppTheme.pageCanvas,
        child: SelectionArea(child: child),
      ),
      floatingActionButton: isBankUser
          ? null
          : FloatingActionButton(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              onPressed: () => _showQuickCreateSheet(context),
              child: const Icon(AppPhosphorIcons.plus),
            ),
      floatingActionButtonLocation: isBankUser
          ? null
          : FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        height: 66,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            const Gap(8),
            if (pinnedItems.isNotEmpty)
              _BottomItem(
                label: pinnedItems[0].label,
                icon: pinnedItems[0].icon,
                active: isPinnedActive(0),
                onTap: () => context.go(pinnedItems[0].path),
              ),
            if (pinnedItems.length > 1)
              _BottomItem(
                label: pinnedItems[1].label,
                icon: pinnedItems[1].icon,
                active: isPinnedActive(1),
                onTap: () => context.go(pinnedItems[1].path),
              ),
            const Spacer(),
            if (pinnedItems.length > 2)
              _BottomItem(
                label: pinnedItems[2].label,
                icon: pinnedItems[2].icon,
                active: isPinnedActive(2),
                onTap: () => context.go(pinnedItems[2].path),
              ),
            _BottomItem(
              label: 'Menü',
              icon: AppPhosphorIcons.gridFour,
              active: overflowActive,
              onTap: () =>
                  _showMobileModulesSheet(context, ref, allowedItems, location),
            ),
            const Gap(8),
          ],
        ),
      ),
    );
  }
}

List<_NavItem> _mobilePinnedItems(List<_NavItem> allowedItems) {
  const preferred = ['panel', 'musteriler', 'is_emirleri'];
  final byPage = {for (final item in allowedItems) item.pageKey: item};
  final result = <_NavItem>[
    for (final key in preferred)
      if (byPage[key] != null) byPage[key]!,
  ];
  for (final item in allowedItems) {
    if (result.length >= 3) break;
    if (!result.any((pinned) => pinned.path == item.path)) result.add(item);
  }
  return result;
}

Future<void> _showMobileModulesSheet(
  BuildContext context,
  WidgetRef ref,
  List<_NavItem> items,
  String location,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: _MobileModulesSheet(
        items: items,
        matchedLocation: location,
        onAccountTap: () {
          Navigator.of(context).pop();
          _showMobileAccountSheet(context, ref);
        },
      ),
    ),
  );
}

class _MobileModulesSheet extends StatefulWidget {
  const _MobileModulesSheet({
    required this.items,
    required this.matchedLocation,
    required this.onAccountTap,
  });

  final List<_NavItem> items;
  final String matchedLocation;
  final VoidCallback onAccountTap;

  @override
  State<_MobileModulesSheet> createState() => _MobileModulesSheetState();
}

class _MobileModulesSheetState extends State<_MobileModulesSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.toLowerCase().trim();
    final visibleItems = normalizedQuery.isEmpty
        ? widget.items
        : widget.items
              .where((item) {
                final subItems = _mobileNavSubItems(item);
                return item.label.toLowerCase().contains(normalizedQuery) ||
                    item.pageKey.toLowerCase().contains(normalizedQuery) ||
                    subItems.any(
                      (subItem) =>
                          subItem.label.toLowerCase().contains(normalizedQuery),
                    );
              })
              .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Gap(14),
              Row(
                children: [
                  Text(
                    'Modüller',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  const _ThemeModeControl(compact: true),
                  IconButton(
                    tooltip: 'Hesap',
                    onPressed: widget.onAccountTap,
                    icon: const Icon(AppPhosphorIcons.userCircle),
                  ),
                ],
              ),
              const Gap(8),
              SizedBox(
                height: 48,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Modül ara',
                    prefixIcon: const Icon(AppPhosphorIcons.magnifyingGlass),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Temizle',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(AppPhosphorIcons.x),
                          ),
                  ),
                ),
              ),
              const Gap(10),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            itemCount: visibleItems.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              final subItems = _mobileNavSubItems(item);
              final active = _isActive(widget.matchedLocation, item.path);
              return _MobileModuleTile(
                item: item,
                subItems: subItems,
                matchedLocation: widget.matchedLocation,
                active: active,
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(item.path);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

List<_FormsNavSubItem> _mobileNavSubItems(_NavItem item) {
  if (item.path == '/banka-panel') return const [];
  if (item.path == '/formlar/banka-rapor') return const [];
  if (item.path == '/formlar') {
    return _formsNavSubItems(item.label == 'Başvuru');
  }
  if (item.pageKey == 'e_fatura') {
    return const [
      _FormsNavSubItem(label: 'Alış Faturası', path: '/e-fatura/alis'),
      _FormsNavSubItem(label: 'Satış Faturası', path: '/e-fatura/satis'),
      _FormsNavSubItem(label: 'Stok/Hizmet', path: '/e-fatura/stok'),
      _FormsNavSubItem(label: 'Cari', path: '/e-fatura/cari'),
      _FormsNavSubItem(label: 'Ayarlar', path: '/e-fatura/ayarlar'),
    ];
  }
  if (item.pageKey == 'finans') {
    return const [
      _FormsNavSubItem(label: 'CRM Finans', path: '/finans'),
      _FormsNavSubItem(
        label: 'Bankalar / Hesaplar',
        path: '/finans/akinsoft/bankalar',
      ),
      _FormsNavSubItem(label: 'Kasa', path: '/finans/akinsoft/kasa'),
      _FormsNavSubItem(
        label: 'Transferler',
        path: '/finans/akinsoft/transferler',
      ),
      _FormsNavSubItem(
        label: 'Masraf Faturaları',
        path: '/finans/akinsoft/masraf',
      ),
    ];
  }
  return const [];
}

List<_FormsNavSubItem> _formsNavSubItems(bool bankOnly) {
  if (bankOnly) {
    return const [_FormsNavSubItem(label: 'Başvuru', path: '/formlar/basvuru')];
  }
  return const [
    _FormsNavSubItem(label: 'Başvuru', path: '/formlar/basvuru'),
    _FormsNavSubItem(label: 'Hurda', path: '/formlar/hurda'),
    _FormsNavSubItem(label: 'Arıza', path: '/formlar/ariza'),
    _FormsNavSubItem(label: 'Devir', path: '/formlar/devir'),
    _FormsNavSubItem(label: 'Seri Takip', path: '/formlar/seri-takip'),
  ];
}

List<_NavItem> _visibleNavItems({
  required Set<String> allowedPages,
  required bool isBankUser,
}) {
  if (isBankUser) return _bankNavItems;
  return _navItems
      .where((item) => allowedPages.contains(item.pageKey))
      .toList(growable: false);
}

class _MobileModuleTile extends StatelessWidget {
  const _MobileModuleTile({
    required this.item,
    required this.subItems,
    required this.matchedLocation,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final List<_FormsNavSubItem> subItems;
  final String matchedLocation;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = _navAccentColor(item.pageKey);
    return Material(
      color: active
          ? accentColor.withValues(alpha: 0.09)
          : AppTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: active
                  ? accentColor.withValues(alpha: 0.24)
                  : AppTheme.border,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: AppTheme.categoryIconWell(
                      accentColor,
                      radius: AppTheme.radiusXs,
                    ),
                    child: Icon(
                      item.icon,
                      size: 19,
                      color: AppTheme.categoryIconFg(accentColor),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? accentColor : AppTheme.text,
                      ),
                    ),
                  ),
                  Icon(
                    active
                        ? AppPhosphorIcons.checkCircle
                        : AppPhosphorIcons.caretRight,
                    size: active ? 20 : 22,
                    color: active ? accentColor : AppTheme.textMuted,
                  ),
                ],
              ),
              if (subItems.isNotEmpty) ...[
                const Gap(8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final subItem in subItems)
                        _MobileSubModuleChip(
                          label: subItem.label,
                          active: _isActive(matchedLocation, subItem.path),
                          color: accentColor,
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go(subItem.path);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSubModuleChip extends StatelessWidget {
  const _MobileSubModuleChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: active ? color.withValues(alpha: 0.35) : AppTheme.border,
      ),
      backgroundColor: active
          ? color.withValues(alpha: 0.11)
          : AppTheme.surface,
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: active ? color : AppTheme.textSoft,
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      onPressed: onTap,
    );
  }
}

Future<void> _showMobileAccountSheet(
  BuildContext context,
  WidgetRef ref,
) async {
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
                      child: Icon(
                        AppPhosphorIcons.userCircle,
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            role == 'admin' ? 'Admin' : 'Personel',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(16),
              Text(
                'Tema',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(8),
              const _MobileThemeModePicker(),
              const Gap(16),
              FilledButton.tonalIcon(
                onPressed: () async {
                  ref
                      .read(apiAccessTokenProvider.notifier)
                      .clear(persist: true);
                  final client = ref.read(supabaseClientProvider);
                  await client?.auth.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  context.go('/giris');
                },
                icon: const Icon(AppPhosphorIcons.signOut, size: 18),
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

/// Transparent wordmark — no chip/pill behind the logo in either theme.
Widget _brandLogoImage({
  required double height,
  Alignment alignment = Alignment.centerLeft,
}) {
  return Image.asset(
    'assets/images/logo_v2.png',
    height: height,
    fit: BoxFit.contain,
    alignment: alignment,
    filterQuality: FilterQuality.high,
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onTap, required this.subtitle});

  final VoidCallback onTap;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Same horizontal inset as _SidebarItem (10) so wordmark lines up with nav icons.
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _brandLogoImage(height: 32),
            const Gap(4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.sidebarTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactBrandButton extends StatelessWidget {
  const _CompactBrandButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Microvise CRM',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _brandLogoImage(height: 28, alignment: Alignment.center),
        ),
      ),
    );
  }
}

class _SidebarIconItem extends StatelessWidget {
  const _SidebarIconItem({
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
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 44,
          decoration: AppTheme.sidebarNavDecoration(active: active),
          child: Center(
            child: Container(
              width: 31,
              height: 31,
              decoration: AppTheme.categoryIconWell(
                accentColor,
                radius: AppTheme.radiusXs,
              ),
              child: AppPhosphorIcon(
                icon,
                size: 18,
                color: AppTheme.categoryIconFg(accentColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactAccountButton extends StatelessWidget {
  const _CompactAccountButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hesap',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
          ),
          child: Icon(
            AppPhosphorIcons.userCircle,
            color: AppTheme.primary,
            size: 21,
          ),
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
          color: AppTheme.surface.withValues(alpha: 0.96),
          border: Border(
            bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.45)),
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: AppTheme.border.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    AppPhosphorIcons.monitor,
                    size: 16,
                    color: AppTheme.textSoft,
                  ),
                  const Gap(8),
                  Text(
                    'Web Panel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSoft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const _ThemeModeControl(),
            const Gap(6),
            IconButton(
              tooltip: 'Bildirimler',
              onPressed: () {},
              icon: Icon(AppPhosphorIcons.bell, color: AppTheme.text),
            ),
            const Gap(6),
            _ProfileButton(),
          ],
        ),
      ),
    );
  }
}

/// Masaüstü üst çubuk + mobil menü için ortak tema seçici.
///
/// `compact: true` yalnızca ikon gösterir (mobil Modüller sayfası);
/// masaüstünde etiket + açılır menü kullanılır.
class _ThemeModeControl extends ConsumerWidget {
  const _ThemeModeControl({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return MenuAnchor(
      builder: (context, controller, child) => Tooltip(
        message: 'Tema: ${themeModeLabelTr(mode)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: compact
              ? SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    themeModeIcon(mode),
                    size: 20,
                    color: AppTheme.textSoft,
                  ),
                )
              : Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                      color: AppTheme.border.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        themeModeIcon(mode),
                        size: 18,
                        color: AppTheme.textSoft,
                      ),
                      const Gap(8),
                      Text(
                        themeModeLabelTr(mode),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Gap(2),
                      Icon(
                        AppPhosphorIcons.caretDown,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                    ],
                  ),
                ),
        ),
      ),
      menuChildren: [
        for (final option in const [
          ThemeMode.light,
          ThemeMode.dark,
          ThemeMode.system,
        ])
          MenuItemButton(
            onPressed: () =>
                ref.read(themeModeProvider.notifier).setMode(option),
            leadingIcon: Icon(
              themeModeIcon(option),
              size: 18,
              color: mode == option ? AppTheme.primary : AppTheme.textSoft,
            ),
            trailingIcon: mode == option
                ? Icon(
                    AppPhosphorIcons.check,
                    size: 16,
                    color: AppTheme.primary,
                  )
                : null,
            child: Text(
              themeModeLabelTr(option),
              style: TextStyle(
                fontWeight: mode == option ? FontWeight.w700 : FontWeight.w500,
                color: AppTheme.text,
              ),
            ),
          ),
      ],
    );
  }
}

/// Mobil hesap sayfasındaki Açık / Koyu / Oto segment seçici.
class _MobileThemeModePicker extends ConsumerWidget {
  const _MobileThemeModePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppTheme.primary;
          return AppTheme.textSoft;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: AppTheme.border.withValues(alpha: 0.7)),
        ),
      ),
      segments: [
        for (final option in const [
          ThemeMode.light,
          ThemeMode.dark,
          ThemeMode.system,
        ])
          ButtonSegment<ThemeMode>(
            value: option,
            icon: Icon(themeModeIcon(option), size: 16),
            label: Text(
              themeModeLabelTr(option),
              overflow: TextOverflow.ellipsis,
            ),
            tooltip: 'Tema: ${themeModeLabelTr(option)}',
          ),
      ],
      selected: {mode},
      onSelectionChanged: (selected) {
        if (selected.isEmpty) return;
        ref.read(themeModeProvider.notifier).setMode(selected.first);
      },
    );
  }
}

/// Masaüstü üst çubuktaki profil düğmesi.
///
/// Önceden her zaman sabit "Profil" metni gösteriyordu (gerçek kullanıcı adı
/// hiç okunmuyordu) ve tek menü öğesi olan "Ayarlar" hiçbir şey yapmıyordu
/// (`onPressed: () {}`). Mobildeki hesap sayfası (`_showMobileAccountSheet`)
/// zaten aynı bilgiyi (isim, rol, çıkış) `currentUserProfileProvider`
/// üzerinden gösteriyordu — burada da aynı, zaten var olan sayfa açılıyor;
/// yeni bir ekran/route icat edilmedi.
class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final name = (profile?.fullName ?? '').trim();
    final label = name.isEmpty ? 'Profil' : name;

    return MenuAnchor(
      builder: (context, controller, child) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.surfaceSoft,
                child: Icon(
                  AppPhosphorIcons.userCircle,
                  size: 16,
                  color: AppTheme.textSoft,
                ),
              ),
              const Gap(10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Gap(6),
              const Icon(AppPhosphorIcons.caretDown, size: 18),
            ],
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(AppPhosphorIcons.gearSix, size: 18),
          onPressed: () => _showMobileAccountSheet(context, ref),
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
    final fg = AppTheme.sidebarNavFg(active: active);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 42,
        decoration: AppTheme.sidebarNavDecoration(active: active),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: AppTheme.categoryIconWell(
                accentColor,
                radius: AppTheme.radiusXs,
              ),
              child: AppPhosphorIcon(
                icon,
                size: 17,
                color: AppTheme.categoryIconFg(accentColor),
              ),
            ),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                  fontSize: 13.5,
                ),
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
    final anySubActive = subItems.any(
      (e) => _isActive(matchedLocation, e.path),
    );
    final isActive = active || anySubActive;
    final fg = AppTheme.sidebarNavFg(active: isActive);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
          onTap: onHeaderTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 42,
            decoration: AppTheme.sidebarNavDecoration(active: isActive),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: AppTheme.categoryIconWell(
                    accentColor,
                    radius: AppTheme.radiusXs,
                  ),
                  child: AppPhosphorIcon(
                    icon,
                    size: 17,
                    color: AppTheme.categoryIconFg(accentColor),
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? AppPhosphorIcons.caretUp
                      : AppPhosphorIcons.caretDown,
                  size: 18,
                  color: fg,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.sidebarText.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Column(
                children: [
                  for (final item in subItems) ...[
                    _SidebarSubItem(
                      label: item.label,
                      active: matchedLocation == item.path,
                      accentColor: accentColor,
                      onTap: () => context.go(item.path),
                    ),
                    if (item != subItems.last) const Gap(2),
                  ],
                ],
              ),
            ),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
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
  // ignore: unused_field
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.sidebarNavFg(active: active);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 36,
        margin: const EdgeInsets.only(left: 18),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: AppTheme.sidebarNavDecoration(active: active),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: active
                    ? (AppTheme.isDark
                          ? AppTheme.primaryDark
                          : AppTheme.sidebarText)
                    : AppTheme.sidebarTextMuted.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                  fontSize: 12.5,
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
    final accent = switch (label) {
      'Panel' => AppTheme.primary,
      'Müşteriler' => AppTheme.purple,
      'İş Emirleri' => AppTheme.success,
      'Menü' => AppTheme.blueBright,
      _ => AppTheme.primary,
    };
    final color = active ? accent : AppTheme.textMuted;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: AppTheme.categoryIconWell(
                  accent,
                  radius: AppTheme.radiusXs,
                ),
                child: AppPhosphorIcon(
                  icon,
                  size: 16,
                  color: AppTheme.categoryIconFg(accent),
                ),
              ),
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
  const _AccountCard({required this.profile, required this.onSignOut});

  final UserProfile? profile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final name = (profile?.fullName ?? '').trim();
    final role = profile?.role == 'admin'
        ? 'Admin'
        : (profile?.isBankLike ?? false)
        ? 'Banka Personeli'
        : 'Personel';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? AppTheme.surfaceMuted.withValues(alpha: 0.55)
            : AppTheme.sidebarText.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: AppTheme.isDark
              ? AppTheme.border.withValues(alpha: 0.65)
              : AppTheme.sidebarText.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppTheme.isDark
                ? AppTheme.primary.withValues(alpha: 0.18)
                : AppTheme.primary.withValues(alpha: 0.18),
            child: Icon(
              AppPhosphorIcons.userCircle,
              size: 17,
              color: AppTheme.isDark
                  ? AppTheme.primaryDark
                  : AppTheme.sidebarText,
            ),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? 'Hesap' : name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.sidebarText,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  role,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.sidebarTextMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Çıkış Yap',
            onPressed: onSignOut,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              AppPhosphorIcons.signOut,
              size: 17,
              color: AppTheme.sidebarTextMuted,
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
      return AppTheme.blue;
    case 'musteriler':
      return AppTheme.blue;
    case 'formlar':
      return AppTheme.orange;
    case 'is_emirleri':
      return AppTheme.green;
    case 'servis':
      return AppTheme.blue;
    case 'raporlar':
      return AppTheme.purple;
    case 'urunler':
      return AppTheme.blue;
    case 'faturalama':
      return AppTheme.orange;
    case 'kdv_analizi':
      return AppTheme.red;
    case 'finans':
      return AppTheme.green;
    case 'tanimlamalar':
      return AppTheme.sidebarTextMuted;
    case 'personel':
      return AppTheme.purple;
    default:
      return AppTheme.blue;
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
            icon: AppPhosphorIcons.userPlus,
            onTap: () {
              Navigator.of(context).pop();
              context.go('/musteriler?yeni=1');
            },
          ),
          _SheetItem(
            title: 'Yeni İş Emri',
            icon: AppPhosphorIcons.listPlus,
            onTap: () {
              Navigator.of(context).pop();
              context.go('/is-emirleri?yeni=1');
            },
          ),
          _SheetItem(
            title: 'Yeni Servis Kaydı',
            icon: AppPhosphorIcons.hammer,
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
      trailing: const Icon(AppPhosphorIcons.caretRight),
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

  _NavItem copyWith({String? path, String? label}) {
    return _NavItem(
      path: path ?? this.path,
      label: label ?? this.label,
      icon: icon,
      pageKey: pageKey,
    );
  }
}

final _navItems = <_NavItem>[
  _NavItem(
    path: '/panel',
    label: 'Panel',
    icon: AppPhosphorIcons.gauge,
    pageKey: 'panel',
  ),
  _NavItem(
    path: '/musteriler',
    label: 'Müşteriler',
    icon: AppPhosphorIcons.addressBook,
    pageKey: 'musteriler',
  ),
  _NavItem(
    path: '/formlar',
    label: 'Formlar',
    icon: AppPhosphorIcons.notePencil,
    pageKey: 'formlar',
  ),
  _NavItem(
    path: '/e-fatura',
    label: 'E-Fatura',
    icon: AppPhosphorIcons.receipt,
    pageKey: 'e_fatura',
  ),
  _NavItem(
    path: '/belgeler',
    label: 'Belgeler',
    icon: AppPhosphorIcons.fileArchive,
    pageKey: 'formlar',
  ),
  _NavItem(
    path: '/is-emirleri',
    label: 'İş Emirleri',
    icon: AppPhosphorIcons.clipboardText,
    pageKey: 'is_emirleri',
  ),
  _NavItem(
    path: '/servis',
    label: 'Servis',
    icon: AppPhosphorIcons.toolbox,
    pageKey: 'servis',
  ),
  _NavItem(
    path: '/raporlar',
    label: 'Raporlar',
    icon: AppPhosphorIcons.presentationChart,
    pageKey: 'raporlar',
  ),
  _NavItem(
    path: '/urunler',
    label: 'Hat & Lisans',
    icon: AppPhosphorIcons.simCard,
    pageKey: 'urunler',
  ),
  _NavItem(
    path: '/faturalama',
    label: 'Faturalama',
    icon: AppPhosphorIcons.invoice,
    pageKey: 'faturalama',
  ),
  _NavItem(
    path: '/finans',
    label: 'Finans',
    icon: AppPhosphorIcons.bank,
    pageKey: 'finans',
  ),
  _NavItem(
    path: '/kdv-analizi',
    label: 'KDV Analizi',
    icon: AppPhosphorIcons.chartDonut,
    pageKey: 'kdv_analizi',
  ),
  _NavItem(
    path: '/tanimlamalar',
    label: 'Tanımlamalar',
    icon: AppPhosphorIcons.slidersHorizontal,
    pageKey: 'tanimlamalar',
  ),
  _NavItem(
    path: '/personel',
    label: 'Personel',
    icon: AppPhosphorIcons.identificationBadge,
    pageKey: 'personel',
  ),
];

final _bankNavItems = <_NavItem>[
  const _NavItem(
    path: '/banka-panel',
    label: 'Panel',
    icon: AppPhosphorIcons.squaresFour,
    pageKey: 'formlar',
  ),
  const _NavItem(
    path: '/formlar/basvuru',
    label: 'Başvuru',
    icon: AppPhosphorIcons.clipboardText,
    pageKey: 'formlar',
  ),
  const _NavItem(
    path: '/formlar/banka-rapor',
    label: 'Rapor',
    icon: AppPhosphorIcons.chartLineUp,
    pageKey: 'formlar',
  ),
];
