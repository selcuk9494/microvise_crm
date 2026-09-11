import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/theme_mode_provider.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_phosphor_icons.dart';
import 'nav_favorites.dart';

class _FormsNavExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

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

class _MutakabatNavExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final mutakabatNavExpandedProvider =
    NotifierProvider<_MutakabatNavExpandedNotifier, bool>(
      _MutakabatNavExpandedNotifier.new,
    );

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    if (profileAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (profileAsync.hasError || profileAsync.value == null) {
      final message = profileAsync.hasError
          ? profileAsync.error.toString().replaceFirst(
              RegExp(r'^Exception:\s*'),
              '',
            )
          : 'Profil yüklenemedi.';
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Oturum açılamadı',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
                ),
                const Gap(16),
                FilledButton(
                  onPressed: () => ref.invalidate(currentUserProfileProvider),
                  child: const Text('Tekrar dene'),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(apiAccessTokenProvider.notifier).clear(),
                  child: const Text('Çıkış'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 640;

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
    Future<void> signOut() async {
      ref.read(apiAccessTokenProvider.notifier).clear(persist: true);
      final client = ref.read(supabaseClientProvider);
      await client?.auth.signOut();
      if (context.mounted) context.go('/giris');
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: DecoratedBox(
        decoration: AppTheme.pageCanvas,
        child: Row(
          children: [
            _DesktopCorporateSidebar(onSignOut: signOut),
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

String _desktopNavLabel(_NavItem item) {
  if (item.pageKey == 'e_fatura') return 'Faturalar';
  return item.label;
}

class _CorporateNav {
  static const width = 248.0;
  static const background = Color(0xFF07111F);
  static const selected = Color(0xFF163056);
  static const hover = Color(0xFF10243F);
  static const field = Color(0xFF0C1A2E);
  static const line = Color(0xFF243656);
  static const muted = Color(0xFF8AA0B8);
  static const faint = Color(0xFF6B8199);
  static const text = Color(0xFFE8EEF6);
  static const accent = Color(0xFF3B82F6);
}

class _CorporateNavEntry {
  const _CorporateNavEntry({required this.item, required this.subs});

  final _NavItem item;
  final List<_FormsNavSubItem> subs;
}

class _CorporateNavSection {
  const _CorporateNavSection({required this.title, required this.entries});

  final String title;
  final List<_CorporateNavEntry> entries;
}

String _corporateSectionTitle(_NavItem item, {required bool isBankUser}) {
  if (isBankUser) return 'GENEL';
  switch (item.pageKey) {
    case 'panel':
    case 'musteriler':
      return 'GENEL';
    case 'formlar':
    case 'tsm_log':
    case 'is_emirleri':
    case 'servis':
    case 'urunler':
      return 'OPERASYON';
    case 'e_fatura':
    case 'faturalama':
      return 'SATIŞ';
    case 'finans':
    case 'mutakabat':
    case 'kdv_analizi':
    case 'raporlar':
      return 'FİNANS';
    default:
      return 'YÖNETİM';
  }
}

List<_CorporateNavSection> _corporateNavSections({
  required List<_NavItem> items,
  required Set<String> allowedPages,
  required bool isBankUser,
}) {
  const order = ['GENEL', 'OPERASYON', 'SATIŞ', 'FİNANS', 'YÖNETİM'];
  final buckets = {for (final title in order) title: <_CorporateNavEntry>[]};
  for (final item in items) {
    buckets[_corporateSectionTitle(item, isBankUser: isBankUser)]!.add(
      _CorporateNavEntry(
        item: item,
        subs: _navSubItemsForItem(
          item,
          allowedPages: allowedPages,
          isBankUser: isBankUser,
        ),
      ),
    );
  }
  return [
    for (final title in order)
      if (buckets[title]!.isNotEmpty)
        _CorporateNavSection(title: title, entries: buckets[title]!),
  ];
}

bool _navQueryMatches(String query, String label) {
  if (query.isEmpty) return true;
  return label.toLowerCase().contains(query);
}

bool _corporateGroupExpanded(
  WidgetRef ref,
  _NavItem item, {
  required bool force,
}) {
  if (force) return true;
  switch (item.pageKey) {
    case 'formlar':
      if (item.path != '/formlar') return true;
      return ref.watch(formsNavExpandedProvider);
    case 'e_fatura':
      return ref.watch(eInvoiceNavExpandedProvider);
    case 'finans':
      return ref.watch(financeNavExpandedProvider);
    case 'mutakabat':
      return ref.watch(mutakabatNavExpandedProvider);
    default:
      return true;
  }
}

void _toggleCorporateGroup(WidgetRef ref, _NavItem item) {
  if (item.pageKey == 'formlar' && item.path == '/formlar') {
    ref.read(formsNavExpandedProvider.notifier).toggle();
    return;
  }
  if (item.pageKey == 'e_fatura') {
    ref.read(eInvoiceNavExpandedProvider.notifier).toggle();
    return;
  }
  if (item.pageKey == 'finans') {
    ref.read(financeNavExpandedProvider.notifier).toggle();
    return;
  }
  if (item.pageKey == 'mutakabat') {
    ref.read(mutakabatNavExpandedProvider.notifier).toggle();
  }
}

class _DesktopCorporateSidebar extends ConsumerStatefulWidget {
  const _DesktopCorporateSidebar({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  ConsumerState<_DesktopCorporateSidebar> createState() =>
      _DesktopCorporateSidebarState();
}

class _DesktopCorporateSidebarState
    extends ConsumerState<_DesktopCorporateSidebar> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final allowedPages = ref.watch(currentUserPagePermissionsProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final isBankUser = profile?.isBankLike ?? false;
    final items = _visibleNavItems(
      allowedPages: allowedPages,
      isBankUser: isBankUser,
    );
    final query = _query.toLowerCase().trim();
    final searching = query.isNotEmpty;
    final sections = _corporateNavSections(
      items: items,
      allowedPages: allowedPages,
      isBankUser: isBankUser,
    );
    final homePath = isBankUser ? '/banka-panel' : '/panel';
    final favoritePaths = ref.watch(navFavoritesProvider);
    final favorites = resolveNavFavorites(
      paths: favoritePaths,
      catalog: _navFavoriteCatalog(
        allowedPages: allowedPages,
        isBankUser: isBankUser,
      ),
    );
    final visibleFavorites = () {
      final filtered = searching
          ? favorites
                .where((item) => _navQueryMatches(query, item.label))
                .toList(growable: false)
          : favorites;
      if (filtered.isNotEmpty || searching || isBankUser) return filtered;
      return resolveNavFavorites(
        paths: kDefaultNavFavoritePaths,
        catalog: _navFavoriteCatalog(
          allowedPages: allowedPages,
          isBankUser: isBankUser,
        ),
      );
    }();
    final pinned = favoritePaths.toSet();

    return Material(
      color: _CorporateNav.background,
      child: SizedBox(
        width: _CorporateNav.width,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CorporateBrandHeader(
                  onTap: () => context.go(homePath),
                ),
                const Gap(14),
                _CorporateSearchField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
                const Gap(14),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (visibleFavorites.isNotEmpty) ...[
                        const _CorporateSectionLabel(title: 'FAVORİLER'),
                        const Gap(4),
                        for (final favorite in visibleFavorites) ...[
                          _CorporateNavRow(
                            label: favorite.label,
                            icon: favorite.icon,
                            active: _isActive(location, favorite.path),
                            pinned: true,
                            pinAlwaysVisible: true,
                            onTap: () => context.go(favorite.path),
                            onTogglePin: () => ref
                                .read(navFavoritesProvider.notifier)
                                .toggle(favorite.path),
                          ),
                          const Gap(2),
                        ],
                        const Gap(10),
                      ],
                      for (final section in sections)
                        ..._sectionSlivers(
                          section: section,
                          location: location,
                          query: query,
                          searching: searching,
                          pinned: pinned,
                        ),
                    ],
                  ),
                ),
                const Gap(10),
                _CorporateAccountFooter(
                  profile: profile,
                  onSignOut: widget.onSignOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sectionSlivers({
    required _CorporateNavSection section,
    required String location,
    required String query,
    required bool searching,
    required Set<String> pinned,
  }) {
    final visible = <_CorporateNavEntry>[];
    final filteredSubs = <String, List<_FormsNavSubItem>>{};
    for (final entry in section.entries) {
      final parentMatch = _navQueryMatches(
        query,
        _desktopNavLabel(entry.item),
      );
      final matchingSubs = entry.subs
          .where((sub) => _navQueryMatches(query, sub.label))
          .toList(growable: false);
      if (!parentMatch && matchingSubs.isEmpty) continue;
      visible.add(entry);
      filteredSubs[entry.item.path] = parentMatch || !searching
          ? entry.subs
          : matchingSubs;
    }
    if (visible.isEmpty) return const [];

    return [
      _CorporateSectionLabel(title: section.title),
      const Gap(4),
      for (final entry in visible) ...[
        _corporateEntry(
          entry: entry,
          location: location,
          subs: filteredSubs[entry.item.path] ?? entry.subs,
          searching: searching,
          pinned: pinned,
        ),
        const Gap(2),
      ],
      const Gap(10),
    ];
  }

  Widget _corporateEntry({
    required _CorporateNavEntry entry,
    required String location,
    required List<_FormsNavSubItem> subs,
    required bool searching,
    required Set<String> pinned,
  }) {
    final childActive = subs.any((sub) => _isActive(location, sub.path));
    final parentActive =
        _isActive(location, entry.item.path) && !childActive;
    final expanded = subs.isEmpty
        ? false
        : _corporateGroupExpanded(ref, entry.item, force: searching);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CorporateNavRow(
          label: _desktopNavLabel(entry.item),
          icon: entry.item.icon,
          active: parentActive || (childActive && !expanded),
          expandable: subs.isNotEmpty,
          expanded: expanded,
          pinned: pinned.contains(entry.item.path),
          onTogglePin: () => ref
              .read(navFavoritesProvider.notifier)
              .toggle(entry.item.path),
          onTap: () {
            if (subs.isEmpty) {
              context.go(entry.item.path);
              return;
            }
            if (!expanded) {
              if (!searching) _toggleCorporateGroup(ref, entry.item);
              if (!childActive && !parentActive) {
                context.go(subs.first.path);
              }
              return;
            }
            if (childActive || parentActive) {
              if (!searching) _toggleCorporateGroup(ref, entry.item);
              return;
            }
            context.go(subs.first.path);
          },
        ),
        if (subs.isNotEmpty && expanded)
          for (final sub in subs)
            _CorporateNavRow(
              label: sub.label,
              icon: entry.item.icon,
              active: _isActive(location, sub.path),
              indent: true,
              pinned: pinned.contains(sub.path),
              onTogglePin: () =>
                  ref.read(navFavoritesProvider.notifier).toggle(sub.path),
              onTap: () => context.go(sub.path),
            ),
      ],
    );
  }
}

class _CorporateBrandHeader extends StatelessWidget {
  const _CorporateBrandHeader({required this.onTap});

  final VoidCallback onTap;

  static const _logoLift = ColorFilter.matrix(<double>[
    1.25, 0, 0, 0, 22,
    0, 1.25, 0, 0, 22,
    0, 0, 1.25, 0, 22,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Microvise ERP CRM',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ColorFiltered(
                colorFilter: _logoLift,
                child: _brandLogoImage(height: 28),
              ),
              const Gap(6),
              const Text(
                'Microvise ERP CRM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CorporateSearchField extends StatelessWidget {
  const _CorporateSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.isNotEmpty;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: _CorporateNav.text, fontSize: 13),
      cursorColor: _CorporateNav.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Ara…',
        hintStyle: const TextStyle(color: _CorporateNav.faint, fontSize: 13),
        filled: true,
        fillColor: _CorporateNav.field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 32,
        ),
        prefixIcon: const Icon(
          AppPhosphorIcons.magnifyingGlass,
          size: 16,
          color: _CorporateNav.muted,
        ),
        suffixIcon: hasQuery
            ? IconButton(
                tooltip: 'Temizle',
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  AppPhosphorIcons.x,
                  size: 14,
                  color: _CorporateNav.muted,
                ),
              )
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _CorporateNav.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _CorporateNav.accent),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _CorporateNav.line),
        ),
      ),
    );
  }
}

class _CorporateSectionLabel extends StatelessWidget {
  const _CorporateSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Text(
        title,
        style: const TextStyle(
          color: _CorporateNav.faint,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _CorporateNavRow extends StatelessWidget {
  const _CorporateNavRow({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.indent = false,
    this.expandable = false,
    this.expanded = false,
    this.pinned = false,
    this.pinAlwaysVisible = false,
    this.onTogglePin,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool indent;
  final bool expandable;
  final bool expanded;
  final bool pinned;
  final bool pinAlwaysVisible;
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : _CorporateNav.muted;
    return _CorporateHoverScope(
      builder: (context, hovered) {
        final showPin =
            onTogglePin != null && (hovered || pinAlwaysVisible);
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: _CorporateNav.hover,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 34),
            padding: EdgeInsets.fromLTRB(indent ? 22 : 8, 6, 4, 6),
            decoration: BoxDecoration(
              color: active ? _CorporateNav.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (indent)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: AppPhosphorIcon(icon, size: 16, color: color),
                  ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      fontSize: indent ? 13 : 13.5,
                    ),
                  ),
                ),
                if (onTogglePin != null)
                  IgnorePointer(
                    ignoring: !showPin,
                    child: Opacity(
                      opacity: showPin ? 1 : 0,
                      child: IconButton(
                        tooltip: pinned
                            ? 'Kısayollardan çıkar'
                            : 'Kısayollara ekle',
                        onPressed: onTogglePin,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: Icon(
                          pinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 13,
                          color: pinned
                              ? const Color(0xFF93C5FD)
                              : _CorporateNav.faint,
                        ),
                      ),
                    ),
                  ),
                if (expandable)
                  Icon(
                    expanded
                        ? AppPhosphorIcons.caretUp
                        : AppPhosphorIcons.caretDown,
                    size: 12,
                    color: _CorporateNav.faint,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CorporateHoverScope extends StatefulWidget {
  const _CorporateHoverScope({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_CorporateHoverScope> createState() => _CorporateHoverScopeState();
}

class _CorporateHoverScopeState extends State<_CorporateHoverScope> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: widget.builder(context, _hovered),
    );
  }
}

class _CorporateAccountFooter extends StatelessWidget {
  const _CorporateAccountFooter({
    required this.profile,
    required this.onSignOut,
  });

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
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _CorporateNav.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: _CorporateNav.accent,
            child: Text(
              _accountInitial(name),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const Gap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? 'Hesap' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _CorporateNav.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  role,
                  style: const TextStyle(
                    color: _CorporateNav.faint,
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
            icon: const Icon(
              AppPhosphorIcons.signOut,
              size: 16,
              color: _CorporateNav.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavPinButton extends StatelessWidget {
  const _NavPinButton({required this.pinned, required this.onPressed});

  final bool pinned;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: pinned ? 'Favorilerden çıkar' : 'Favorilere ekle',
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      icon: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        size: 13,
        color: pinned ? AppTheme.primary : AppTheme.sidebarTextMuted,
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
    final favorites = resolveNavFavorites(
      paths: ref.watch(navFavoritesProvider),
      catalog: _navFavoriteCatalog(
        allowedPages: allowedPages,
        isBankUser: isBankUser,
      ),
    );
    final pinnedItems = _mobilePinnedItems(allowedItems, favorites: favorites);
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

List<_NavItem> _mobilePinnedItems(
  List<_NavItem> allowedItems, {
  List<NavFavoriteTarget> favorites = const [],
}) {
  final byPath = {for (final item in allowedItems) item.path: item};
  final result = <_NavItem>[];
  void addItem(_NavItem item) {
    if (result.length >= 3) return;
    if (result.any((pinned) => pinned.path == item.path)) return;
    result.add(item);
  }

  for (final favorite in favorites) {
    final existing = byPath[favorite.path];
    addItem(
      existing ??
          _NavItem(
            path: favorite.path,
            label: favorite.label,
            icon: favorite.icon,
            pageKey: favorite.pageKey,
          ),
    );
  }
  const preferred = ['panel', 'musteriler', 'is_emirleri'];
  final byPage = {for (final item in allowedItems) item.pageKey: item};
  for (final key in preferred) {
    final item = byPage[key];
    if (item != null) addItem(item);
  }
  for (final item in allowedItems) {
    addItem(item);
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
        allowedPages: ref.read(currentUserPagePermissionsProvider),
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
    required this.allowedPages,
    required this.onAccountTap,
  });

  final List<_NavItem> items;
  final String matchedLocation;
  final Set<String> allowedPages;
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
                final subItems = _mobileNavSubItems(item, widget.allowedPages);
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
              final subItems = _mobileNavSubItems(item, widget.allowedPages);
              final active = _isActive(widget.matchedLocation, item.path);
              return Consumer(
                builder: (context, ref, _) {
                  final favoritePaths = ref.watch(navFavoritesProvider).toSet();
                  return _MobileModuleTile(
                    item: item,
                    subItems: subItems,
                    matchedLocation: widget.matchedLocation,
                    active: active,
                    pinned: favoritePaths.contains(item.path),
                    favoritePaths: favoritePaths,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(item.path);
                    },
                    onToggleFavorite: () => ref
                        .read(navFavoritesProvider.notifier)
                        .toggle(item.path),
                    onToggleSubFavorite: (path) =>
                        ref.read(navFavoritesProvider.notifier).toggle(path),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

List<_FormsNavSubItem> _eInvoiceNavSubItems(Set<String> allowedPages) {
  final items = <_FormsNavSubItem>[];
  if (allowedPages.contains(kPageEInvoice)) {
    items.add(
      const _FormsNavSubItem(label: 'Alış Faturası', path: '/e-fatura/alis'),
    );
    items.add(
      const _FormsNavSubItem(label: 'Satış Faturası', path: '/e-fatura/satis'),
    );
    items.add(
      const _FormsNavSubItem(label: 'Teklif', path: '/e-fatura/teklif'),
    );
    items.addAll(const [
      _FormsNavSubItem(label: 'Stok/Hizmet', path: '/e-fatura/stok'),
      _FormsNavSubItem(label: 'Cari', path: '/e-fatura/cari'),
      _FormsNavSubItem(
        label: 'Sanal POS ile ödenenler',
        path: '/e-fatura/sanal-pos',
      ),
      _FormsNavSubItem(
        label: 'Tekrarlayan ödemeler',
        path: '/e-fatura/tekrarlayan',
      ),
      _FormsNavSubItem(label: 'E-Fatura Ayarları', path: '/e-fatura/ayarlar'),
    ]);
  } else if (allowedPages.contains(kPageQuotes)) {
    items.add(
      const _FormsNavSubItem(label: 'Teklif', path: '/e-fatura/teklif'),
    );
  }
  if (allowedPages.contains(kPageEInvoice) ||
      allowedPages.contains(kPageQuotes)) {
    items.add(
      const _FormsNavSubItem(
        label: 'Teklif Ayarları',
        path: '/e-fatura/teklif/ayarlar',
      ),
    );
  }
  return items;
}

const _financeNavSubItems = <_FormsNavSubItem>[
  _FormsNavSubItem(label: 'CRM Finans', path: '/finans'),
  _FormsNavSubItem(label: 'Kapatılan Ödemeler', path: '/finans/odemeler'),
  _FormsNavSubItem(
    label: 'Bankalar / Hesaplar',
    path: '/finans/akinsoft/bankalar',
  ),
  _FormsNavSubItem(label: 'Kasa', path: '/finans/akinsoft/kasa'),
  _FormsNavSubItem(label: 'Transferler', path: '/finans/akinsoft/transferler'),
  _FormsNavSubItem(label: 'Masraf Faturaları', path: '/finans/akinsoft/masraf'),
];

List<_FormsNavSubItem> _mobileNavSubItems(
  _NavItem item,
  Set<String> allowedPages,
) {
  if (item.path == '/banka-panel') return const [];
  if (item.path == '/formlar/banka-rapor') return const [];
  if (item.path == '/formlar') {
    return _formsNavSubItems(item.label == 'Başvuru');
  }
  if (item.pageKey == 'e_fatura') {
    return _eInvoiceNavSubItems(allowedPages);
  }
  if (item.pageKey == 'finans') {
    return _financeNavSubItems;
  }
  if (item.pageKey == 'mutakabat') {
    return const [
      _FormsNavSubItem(label: 'Aylık Kayıtlar', path: '/mutakabat'),
      _FormsNavSubItem(label: 'Birim Fiyatlar', path: '/mutakabat/fiyatlar'),
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
      .where((item) {
        if (item.pageKey == kPageEInvoice) {
          return allowedPages.contains(kPageEInvoice) ||
              allowedPages.contains(kPageQuotes);
        }
        return allowedPages.contains(item.pageKey);
      })
      .toList(growable: false);
}

List<NavFavoriteTarget> _navFavoriteCatalog({
  required Set<String> allowedPages,
  required bool isBankUser,
}) {
  final catalog = <NavFavoriteTarget>[];
  final seen = <String>{};
  void add({
    required String path,
    required String label,
    required IconData icon,
    required String pageKey,
  }) {
    if (!seen.add(path)) return;
    catalog.add(
      NavFavoriteTarget(path: path, label: label, icon: icon, pageKey: pageKey),
    );
  }

  for (final item in _visibleNavItems(
    allowedPages: allowedPages,
    isBankUser: isBankUser,
  )) {
    add(
      path: item.path,
      label: item.pageKey == 'e_fatura' ? 'Faturalar' : item.label,
      icon: item.icon,
      pageKey: item.pageKey,
    );
    for (final sub in _mobileNavSubItems(item, allowedPages)) {
      add(
        path: sub.path,
        label: sub.label,
        icon: item.icon,
        pageKey: item.pageKey,
      );
    }
  }
  return catalog;
}

class _MobileModuleTile extends StatelessWidget {
  const _MobileModuleTile({
    required this.item,
    required this.subItems,
    required this.matchedLocation,
    required this.active,
    required this.pinned,
    required this.favoritePaths,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onToggleSubFavorite,
  });

  final _NavItem item;
  final List<_FormsNavSubItem> subItems;
  final String matchedLocation;
  final bool active;
  final bool pinned;
  final Set<String> favoritePaths;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final ValueChanged<String> onToggleSubFavorite;

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
                  _NavPinButton(pinned: pinned, onPressed: onToggleFavorite),
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
                          pinned: favoritePaths.contains(subItem.path),
                          color: accentColor,
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go(subItem.path);
                          },
                          onLongPress: () => onToggleSubFavorite(subItem.path),
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
    required this.pinned,
    required this.color,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final bool active;
  final bool pinned;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: (active || pinned)
              ? color.withValues(alpha: 0.35)
              : AppTheme.border,
        ),
        backgroundColor: active
            ? color.withValues(alpha: 0.11)
            : AppTheme.surface,
        avatar: pinned ? Icon(Icons.push_pin, size: 14, color: color) : null,
        label: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: active ? color : AppTheme.textSoft,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        onPressed: onTap,
      ),
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
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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

List<_FormsNavSubItem> _navSubItemsForItem(
  _NavItem item, {
  required Set<String> allowedPages,
  required bool isBankUser,
}) {
  if (item.path == '/formlar' && !isBankUser) {
    return _formsNavSubItems(isBankUser);
  }
  if (item.pageKey == 'e_fatura') {
    return _eInvoiceNavSubItems(allowedPages);
  }
  if (item.pageKey == 'finans') {
    return _financeNavSubItems;
  }
  if (item.pageKey == 'mutakabat') {
    return const [
      _FormsNavSubItem(label: 'Aylık Kayıtlar', path: '/mutakabat'),
      _FormsNavSubItem(label: 'Birim Fiyatlar', path: '/mutakabat/fiyatlar'),
    ];
  }
  return const [];
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

class _FormsNavSubItem {
  const _FormsNavSubItem({required this.label, required this.path});

  final String label;
  final String path;
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


String _accountInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'H';
  return String.fromCharCodes(trimmed.runes.take(1)).toUpperCase();
}

Color _navAccentColor(String pageKey) {
  switch (pageKey) {
    case 'panel':
      return AppTheme.blue;
    case 'musteriler':
      return AppTheme.blue;
    case 'formlar':
      return AppTheme.orange;
    case 'tsm_log':
      return AppTheme.orange;
    case 'e_fatura':
      return AppTheme.blue;
    case 'teklif':
      return AppTheme.blue;
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
    case 'mutakabat':
      return AppTheme.orange;
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
    path: '/tsm-log',
    label: 'TSM Log',
    icon: AppPhosphorIcons.fileMagnifyingGlass,
    pageKey: 'tsm_log',
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
    path: '/mutakabat',
    label: 'Mutakabat',
    icon: AppPhosphorIcons.arrowsLeftRight,
    pageKey: 'mutakabat',
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
