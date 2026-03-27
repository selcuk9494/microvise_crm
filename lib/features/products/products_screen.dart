import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../billing/billing_screen.dart';

final productSearchProvider = NotifierProvider<ProductSearchNotifier, String>(
  ProductSearchNotifier.new,
);
final showPassiveProvider = NotifierProvider<ShowPassiveNotifier, bool>(
  ShowPassiveNotifier.new,
);

class ProductSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

class ShowPassiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final issuedLinesProvider = FutureProvider<List<IssuedLine>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final search = ref.watch(productSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final isAdmin = ref.watch(isAdminProvider);

  var q = client
      .from('lines')
      .select(
        'id,label,number,sim_number,starts_at,ends_at,is_active,customer_id,branch_id,customers(name),branches(name)',
      );

  if (!(isAdmin && showPassive)) {
    q = q.eq('is_active', true);
  }

  if (search.isNotEmpty) {
    q = q.or('number.ilike.%$search%,sim_number.ilike.%$search%');
  }

  final rows = await q.order('ends_at', ascending: true).limit(500);

  return (rows as List)
      .map((e) {
        final map = e as Map<String, dynamic>;
        final customer = map['customers'] as Map<String, dynamic>?;
        final branch = map['branches'] as Map<String, dynamic>?;
        return IssuedLine.fromJson({
          ...map,
          'customer_name': customer?['name'],
          'branch_name': branch?['name'],
        });
      })
      .toList(growable: false);
});

final issuedLicensesProvider = FutureProvider<List<IssuedLicense>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final search = ref.watch(productSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final isAdmin = ref.watch(isAdminProvider);

  var q = client
      .from('licenses')
      .select(
        'id,name,license_type,starts_at,ends_at,is_active,customer_id,customers(name)',
      );

  if (!(isAdmin && showPassive)) {
    q = q.eq('is_active', true);
  }

  if (search.isNotEmpty) {
    q = q.ilike('name', '%$search%');
  }

  final rows = await q.order('ends_at', ascending: true).limit(500);
  return (rows as List)
      .map((e) {
        final map = e as Map<String, dynamic>;
        final customer = map['customers'] as Map<String, dynamic>?;
        return IssuedLicense.fromJson({
          ...map,
          'customer_name': customer?['name'],
        });
      })
      .toList(growable: false);
});

final customersLookupProvider = FutureProvider<List<CustomerLookup>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('customers')
      .select('id,name,is_active')
      .order('name');
  return (rows as List)
      .map((e) => CustomerLookup.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final showPassive = ref.watch(showPassiveProvider);

    return DefaultTabController(
      length: 2,
      child: AppPageLayout(
        title: 'Hat & Lisanslar',
        subtitle: 'Verilen hatlar ve GMP3 lisansları tek listede.',
        body: Column(
          children: [
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Ara',
                        hintText: 'Hat numarası / SIM / Lisans adı',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) =>
                          ref.read(productSearchProvider.notifier).set(v),
                    ),
                  ),
                  const Gap(12),
                  if (isAdmin)
                    Row(
                      children: [
                        Switch.adaptive(
                          value: showPassive,
                          onChanged: (v) =>
                              ref.read(showPassiveProvider.notifier).set(v),
                        ),
                        const Gap(6),
                        Text(
                          'Pasif',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF475569)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Gap(12),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    tabs: [
                      Tab(text: 'Hatlar'),
                      Tab(text: 'Lisanslar (GMP3)'),
                    ],
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: 740,
                    child: TabBarView(
                      children: [
                        _LinesTab(isAdmin: isAdmin),
                        _LicensesTab(isAdmin: isAdmin),
                      ],
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

class _LinesTab extends ConsumerWidget {
  const _LinesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesAsync = ref.watch(issuedLinesProvider);
    final licensesAsync = ref.watch(issuedLicensesProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: linesAsync.when(
        data: (items) => licensesAsync.when(
          data: (licenses) {
            final licensedCustomerIds = licenses
                .where((license) => license.licenseType == 'gmp3')
                .map((license) => license.customerId)
                .toSet();
            final lineOnlyItems = items
                .where((line) => !licensedCustomerIds.contains(line.customerId))
                .toList(growable: false);

            if (lineOnlyItems.isEmpty) {
              return const _Empty(
                text: 'Sadece hatti olan musteri kaydi bulunmuyor.',
              );
            }
            return ListView.separated(
              itemCount: lineOnlyItems.length,
              separatorBuilder: (context, index) => const Gap(10),
              itemBuilder: (context, index) =>
                  _LineRow(item: lineOnlyItems[index], isAdmin: isAdmin),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const _Empty(text: 'Lisanslar yuklenemedi.'),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Hatlar yuklenemedi.'),
      ),
    );
  }
}

class _LicensesTab extends ConsumerWidget {
  const _LicensesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licensesAsync = ref.watch(issuedLicensesProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: licensesAsync.when(
        data: (items) {
          final gmp3 = items.where((e) => e.licenseType == 'gmp3').toList();
          if (gmp3.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: gmp3.length,
            separatorBuilder: (context, index) => const Gap(10),
            itemBuilder: (context, index) =>
                _LicenseRow(item: gmp3[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const _Empty(text: 'Lisanslar yüklenemedi.'),
      ),
    );
  }
}

class _LineRow extends ConsumerStatefulWidget {
  const _LineRow({required this.item, required this.isAdmin});

  final IssuedLine item;
  final bool isAdmin;

  @override
  ConsumerState<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends ConsumerState<_LineRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final endsAt = item.endsAt;
    final now = DateTime.now();

    final tone = !item.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
        ? AppBadgeTone.neutral
        : endsAt.isBefore(now)
        ? AppBadgeTone.error
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? AppBadgeTone.warning
        : AppBadgeTone.success;

    final statusLabel = !item.isActive
        ? 'Pasif'
        : endsAt == null
        ? 'Tarihsiz'
        : endsAt.isBefore(now)
        ? 'Bitmiş'
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? 'Yaklaşıyor'
        : 'Aktif';

    final dateText = endsAt == null
        ? '—'
        : DateFormat('d MMM y', 'tr_TR').format(endsAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.number ?? 'Hat',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    decoration: item.isActive
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                ),
                const Gap(4),
                Text(
                  [
                    item.customerName ?? '—',
                    if (item.branchName?.trim().isNotEmpty ?? false)
                      item.branchName!,
                    if (item.simNumber?.trim().isNotEmpty ?? false)
                      'SIM: ${item.simNumber}',
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const Gap(4),
                Text(
                  'Bitiş: $dateText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const Gap(10),
          AppBadge(label: statusLabel, tone: tone),
          if (widget.isAdmin) ...[
            const Gap(10),
            MenuAnchor(
              builder: (context, controller, _) => OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('İşlem'),
              ),
              menuChildren: [
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _showEditLineDialog(context, ref, line: item);
                      ref.invalidate(issuedLinesProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Düzenle'),
                ),
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _extendLineAndQueueInvoice(
                        context,
                        ref,
                        line: item,
                      );
                      ref.invalidate(issuedLinesProvider);
                      ref.invalidate(invoiceItemsProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Süre Uzat'),
                ),
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _transferLine(context, ref, line: item);
                      ref.invalidate(issuedLinesProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Devir Et'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LicenseRow extends ConsumerStatefulWidget {
  const _LicenseRow({required this.item, required this.isAdmin});

  final IssuedLicense item;
  final bool isAdmin;

  @override
  ConsumerState<_LicenseRow> createState() => _LicenseRowState();
}

class _LicenseRowState extends ConsumerState<_LicenseRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final endsAt = item.endsAt;
    final now = DateTime.now();

    final tone = !item.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
        ? AppBadgeTone.neutral
        : endsAt.isBefore(now)
        ? AppBadgeTone.error
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? AppBadgeTone.warning
        : AppBadgeTone.success;

    final statusLabel = !item.isActive
        ? 'Pasif'
        : endsAt == null
        ? 'Tarihsiz'
        : endsAt.isBefore(now)
        ? 'Bitmiş'
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? 'Yaklaşıyor'
        : 'Aktif';

    final dateText = endsAt == null
        ? '—'
        : DateFormat('d MMM y', 'tr_TR').format(endsAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    decoration: item.isActive
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                ),
                const Gap(4),
                Text(
                  item.customerName ?? '—',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const Gap(4),
                Text(
                  'Bitiş: $dateText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const Gap(10),
          AppBadge(label: statusLabel, tone: tone),
          if (widget.isAdmin) ...[
            const Gap(10),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await _extendLicenseAndQueueInvoice(
                          context,
                          ref,
                          license: item,
                        );
                        ref.invalidate(issuedLicensesProvider);
                        ref.invalidate(invoiceItemsProvider);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Süre Uzat'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showEditLineDialog(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final labelController = TextEditingController(text: line.label ?? '');
  final numberController = TextEditingController(text: line.number ?? '');
  final simController = TextEditingController(text: line.simNumber ?? '');
  DateTime? startsAt = line.startsAt;
  DateTime? endsAt = line.endsAt;
  bool saving = false;

  Future<void> pickStart(StateSetter setState) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startsAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() => startsAt = picked);
  }

  Future<void> pickEnd(StateSetter setState) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endsAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() => endsAt = picked);
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hat Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: numberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Hat Numarası'),
                ),
                const Gap(12),
                TextField(
                  controller: simController,
                  decoration: const InputDecoration(labelText: 'SIM Numarası'),
                ),
                const Gap(12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Etiket'),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: saving ? null : () => pickStart(setState),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç',
                          ),
                          child: Text(
                            startsAt == null
                                ? '—'
                                : DateFormat(
                                    'd MMM y',
                                    'tr_TR',
                                  ).format(startsAt!),
                          ),
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: saving ? null : () => pickEnd(setState),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Bitiş'),
                          child: Text(
                            endsAt == null
                                ? '—'
                                : DateFormat(
                                    'd MMM y',
                                    'tr_TR',
                                  ).format(endsAt!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final number = numberController.text.trim();
                                if (number.isEmpty) return;
                                setState(() => saving = true);
                                try {
                                  final endStr = endsAt
                                      ?.toIso8601String()
                                      .substring(0, 10);
                                  await client
                                      .from('lines')
                                      .update({
                                        'number': number,
                                        'sim_number':
                                            simController.text.trim().isEmpty
                                            ? null
                                            : simController.text.trim(),
                                        'label':
                                            labelController.text.trim().isEmpty
                                            ? null
                                            : labelController.text.trim(),
                                        'starts_at': startsAt
                                            ?.toIso8601String()
                                            .substring(0, 10),
                                        'ends_at': endStr,
                                        'expires_at': endStr,
                                      })
                                      .eq('id', line.id);

                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Hat güncellendi.'),
                                    ),
                                  );
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Hat güncellenemedi.'),
                                    ),
                                  );
                                } finally {
                                  setState(() => saving = false);
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  labelController.dispose();
  numberController.dispose();
  simController.dispose();
}

Future<void> _extendLineAndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final now = DateTime.now();
  final baseYear = (line.endsAt != null && line.endsAt!.isAfter(now))
      ? line.endsAt!.year
      : now.year;
  final newEnd = DateTime(baseYear + 1, 12, 31);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);

  final amountController = TextEditingController();
  String currency = 'TRY';

  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hat Süre Uzat',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(10),
                Text(
                  'Yeni bitiş tarihi: ${DateFormat('d MMM y', 'tr_TR').format(newEnd)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tutar (opsiyonel)',
                    hintText: '0.00',
                  ),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  ],
                  onChanged: (v) => setState(() => currency = v ?? 'TRY'),
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Uzat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (confirm != true) {
    amountController.dispose();
    return;
  }

  try {
    await client
        .from('lines')
        .update({'ends_at': newEndStr, 'expires_at': newEndStr})
        .eq('id', line.id);

    final amountRaw = amountController.text.trim().replaceAll(',', '.');
    final amount = amountRaw.isEmpty ? null : double.tryParse(amountRaw);

    await client.from('invoice_items').insert({
      'customer_id': line.customerId,
      'item_type': 'line_renewal',
      'source_table': 'lines',
      'source_id': line.id,
      'description':
          'Hat uzatma (${line.number ?? ''}) (yeni bitiş: $newEndStr)',
      'amount': amount,
      'currency': currency,
      'status': 'pending',
      'created_by': client.auth.currentUser?.id,
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hat uzatıldı ve faturalama listesine eklendi.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
    }
  } finally {
    amountController.dispose();
  }
}

Future<void> _transferLine(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final customers = await ref.read(customersLookupProvider.future);
  if (!context.mounted) return;

  final selected = await showDialog<CustomerLookup?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TransferDialog(
      customers: customers
          .where((c) => c.id != line.customerId)
          .toList(growable: false),
    ),
  );
  if (!context.mounted) return;
  if (selected == null) return;

  try {
    await client.from('line_transfers').insert({
      'line_id': line.id,
      'from_customer_id': line.customerId,
      'to_customer_id': selected.id,
      'transferred_by': client.auth.currentUser?.id,
    });

    await client
        .from('lines')
        .update({
          'customer_id': selected.id,
          'branch_id': null,
          'transferred_at': DateTime.now().toIso8601String(),
          'transferred_by': client.auth.currentUser?.id,
        })
        .eq('id', line.id);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hat devredildi.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hat devredilemedi.')));
    }
  }
}

Future<void> _extendLicenseAndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLicense license,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final now = DateTime.now();
  final baseYear = (license.endsAt != null && license.endsAt!.isAfter(now))
      ? license.endsAt!.year
      : now.year;
  final newEnd = DateTime(baseYear + 1, 12, 31);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);

  final amountController = TextEditingController();
  String currency = 'TRY';

  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Lisans Süre Uzat',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(10),
                Text(
                  'Yeni bitiş tarihi: ${DateFormat('d MMM y', 'tr_TR').format(newEnd)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tutar (opsiyonel)',
                    hintText: '0.00',
                  ),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  ],
                  onChanged: (v) => setState(() => currency = v ?? 'TRY'),
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Uzat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (confirm != true) {
    amountController.dispose();
    return;
  }

  try {
    await client
        .from('licenses')
        .update({'ends_at': newEndStr, 'expires_at': newEndStr})
        .eq('id', license.id);

    final amountRaw = amountController.text.trim().replaceAll(',', '.');
    final amount = amountRaw.isEmpty ? null : double.tryParse(amountRaw);

    await client.from('invoice_items').insert({
      'customer_id': license.customerId,
      'item_type': 'gmp3_renewal',
      'source_table': 'licenses',
      'source_id': license.id,
      'description': 'GMP3 uzatma (${license.name}) (yeni bitiş: $newEndStr)',
      'amount': amount,
      'currency': currency,
      'status': 'pending',
      'created_by': client.auth.currentUser?.id,
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lisans uzatıldı ve faturalama listesine eklendi.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
    }
  } finally {
    amountController.dispose();
  }
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.customers});

  final List<CustomerLookup> customers;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  CustomerLookup? _selected;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hat Devir',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(12),
              Autocomplete<CustomerLookup>(
                optionsBuilder: (text) {
                  final q = text.text.trim().toLowerCase();
                  final list = widget.customers
                      .where((c) => c.isActive)
                      .toList(growable: false);
                  if (q.isEmpty) return list.take(20);
                  return list
                      .where((c) => c.name.toLowerCase().contains(q))
                      .take(20);
                },
                displayStringForOption: (o) => o.name,
                onSelected: (o) => setState(() => _selected = o),
                fieldViewBuilder: (context, controller, focusNode, _) =>
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Müşteri',
                        hintText: 'Firma adı yazın ve seçin',
                      ),
                      onChanged: (_) => setState(() => _selected = null),
                    ),
              ),
              const Gap(18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                      child: const Text('Devir Et'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

class IssuedLine {
  const IssuedLine({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.branchId,
    required this.branchName,
    required this.label,
    required this.number,
    required this.simNumber,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String? branchId;
  final String? branchName;
  final String? label;
  final String? number;
  final String? simNumber;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory IssuedLine.fromJson(Map<String, dynamic> json) {
    return IssuedLine(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      branchId: json['branch_id']?.toString(),
      branchName: json['branch_name']?.toString(),
      label: json['label']?.toString(),
      number: json['number']?.toString(),
      simNumber: json['sim_number']?.toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt:
          DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class IssuedLicense {
  const IssuedLicense({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.name,
    required this.licenseType,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String name;
  final String licenseType;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory IssuedLicense.fromJson(Map<String, dynamic> json) {
    return IssuedLicense(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      name: (json['name'] ?? '').toString(),
      licenseType: (json['license_type'] ?? 'gmp3').toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt:
          DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CustomerLookup {
  const CustomerLookup({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory CustomerLookup.fromJson(Map<String, dynamic> json) {
    return CustomerLookup(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
