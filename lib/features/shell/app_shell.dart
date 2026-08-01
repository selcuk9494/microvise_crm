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
                  color: AppTheme.isDark
                      ? AppTheme.border.withValues(alpha: 0.55)
                      : const Color(0xFF151B26),
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
                        onTap: () =>
                            context.go(isBankUser ? '/banka-panel' : '/panel'),
                      )
                    else
                      _BrandHeader(
                        subtitle: isBankUser ? 'WebCR' : 'CRM & Servis',
                        onTap: () =>
                            context.go(isBankUser ? '/banka-panel' : '/panel'),
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
                                subItems: [
                                  _FormsNavSubItem(
                                    label: 'Faturalar',
                                    path: '/e-fatura',
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
                            onTap: () => _showMobileAccountSheet(context, ref),
                          )
                        : _AccountCard(
                            profile: ref
                                .watch(currentUserProfileProvider)
                                .value,
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
                Expanded(
                  child: ClipRect(
                    child: SelectionArea(child: child),
                  ),
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
              child: const Icon(Icons.add_rounded),
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
              icon: Icons.apps_outlined,
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
                  IconButton(
                    tooltip: 'Hesap',
                    onPressed: widget.onAccountTap,
                    icon: const Icon(Icons.person_rounded),
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
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Temizle',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
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
      _FormsNavSubItem(label: 'Faturalar', path: '/e-fatura'),
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
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, size: 20, color: accentColor),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                        color: active ? accentColor : AppTheme.text,
                      ),
                    ),
                  ),
                  Icon(
                    active
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
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
              const Gap(12),
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
                icon: const Icon(Icons.logout_rounded, size: 18),
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
          child: _brandLogoImage(
            height: 28,
            alignment: Alignment.center,
          ),
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
  // Kept for call-site parity with expanded nav items (mobile accents).
  // ignore: unused_field
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
          child: Icon(
            icon,
            size: 20,
            color: AppTheme.sidebarNavFg(active: active),
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
            Icons.person_rounded,
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
          color: AppTheme.isDark
              ? AppTheme.surface.withValues(alpha: 0.72)
              : AppTheme.surface.withValues(alpha: 0.94),
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
                    Icons.monitor_rounded,
                    size: 16,
                    color: AppTheme.primary,
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
              icon: Icon(
                Icons.notifications_none_rounded,
                color: AppTheme.text,
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

class _ThemeModeControl extends ConsumerWidget {
  const _ThemeModeControl();

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
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  themeModeIcon(mode),
                  size: 18,
                  color: AppTheme.primary,
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
                  Icons.expand_more_rounded,
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
            onPressed: () => ref.read(themeModeProvider.notifier).setMode(option),
            leadingIcon: Icon(
              themeModeIcon(option),
              size: 18,
              color: mode == option ? AppTheme.primary : AppTheme.textSoft,
            ),
            trailingIcon: mode == option
                ? Icon(Icons.check_rounded, size: 16, color: AppTheme.primary)
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
            color: AppTheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ),
              const Gap(10),
              Text('Profil', style: Theme.of(context).textTheme.bodyMedium),
              const Gap(6),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(onPressed: () {}, child: const Text('Ayarlar')),
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
        height: 42,
        decoration: AppTheme.sidebarNavDecoration(active: active),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(icon, size: 19, color: fg),
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
  // ignore: unused_field
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
                Icon(icon, size: 19, color: fg),
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
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
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
    final color = active ? AppTheme.primary : AppTheme.textMuted;
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
              Icons.person_outline_rounded,
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
              Icons.logout_rounded,
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
            icon: Icons.person_add_alt_outlined,
            onTap: () {
              Navigator.of(context).pop();
              context.go('/musteriler?yeni=1');
            },
          ),
          _SheetItem(
            title: 'Yeni İş Emri',
            icon: Icons.note_add_outlined,
            onTap: () {
              Navigator.of(context).pop();
              context.go('/is-emirleri?yeni=1');
            },
          ),
          _SheetItem(
            title: 'Yeni Servis Kaydı',
            icon: Icons.handyman_outlined,
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
    icon: Icons.home_outlined,
    pageKey: 'panel',
  ),
  _NavItem(
    path: '/musteriler',
    label: 'Müşteriler',
    icon: Icons.groups_outlined,
    pageKey: 'musteriler',
  ),
  _NavItem(
    path: '/formlar',
    label: 'Formlar',
    icon: Icons.article_outlined,
    pageKey: 'formlar',
  ),
  _NavItem(
    path: '/e-fatura',
    label: 'E-Fatura',
    icon: Icons.receipt_long_outlined,
    pageKey: 'e_fatura',
  ),
  _NavItem(
    path: '/belgeler',
    label: 'Belgeler',
    icon: Icons.folder_outlined,
    pageKey: 'formlar',
  ),
  _NavItem(
    path: '/is-emirleri',
    label: 'İş Emirleri',
    icon: Icons.view_kanban_outlined,
    pageKey: 'is_emirleri',
  ),
  _NavItem(
    path: '/servis',
    label: 'Servis',
    icon: Icons.handyman_outlined,
    pageKey: 'servis',
  ),
  _NavItem(
    path: '/raporlar',
    label: 'Raporlar',
    icon: Icons.bar_chart_outlined,
    pageKey: 'raporlar',
  ),
  _NavItem(
    path: '/urunler',
    label: 'Hat & Lisans',
    icon: Icons.sim_card_outlined,
    pageKey: 'urunler',
  ),
  _NavItem(
    path: '/faturalama',
    label: 'Faturalama',
    icon: Icons.payments_outlined,
    pageKey: 'faturalama',
  ),
  _NavItem(
    path: '/finans',
    label: 'Finans',
    icon: Icons.account_balance_wallet_outlined,
    pageKey: 'finans',
  ),
  _NavItem(
    path: '/kdv-analizi',
    label: 'KDV Analizi',
    icon: Icons.pie_chart_outline,
    pageKey: 'kdv_analizi',
  ),
  _NavItem(
    path: '/tanimlamalar',
    label: 'Tanımlamalar',
    icon: Icons.settings_outlined,
    pageKey: 'tanimlamalar',
  ),
  _NavItem(
    path: '/personel',
    label: 'Personel',
    icon: Icons.manage_accounts_outlined,
    pageKey: 'personel',
  ),
];

final _bankNavItems = <_NavItem>[
  const _NavItem(
    path: '/banka-panel',
    label: 'Panel',
    icon: Icons.home_outlined,
    pageKey: 'formlar',
  ),
  const _NavItem(
    path: '/formlar/basvuru',
    label: 'Başvuru',
    icon: Icons.article_outlined,
    pageKey: 'formlar',
  ),
  const _NavItem(
    path: '/formlar/banka-rapor',
    label: 'Rapor',
    icon: Icons.bar_chart_outlined,
    pageKey: 'formlar',
  ),
];
