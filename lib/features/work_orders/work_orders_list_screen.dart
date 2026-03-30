import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'work_order_create_dialog.dart';
import 'work_order_detail_sheet.dart';
import 'work_orders_providers.dart';

class WorkOrdersListScreen extends ConsumerStatefulWidget {
  const WorkOrdersListScreen({super.key});

  @override
  ConsumerState<WorkOrdersListScreen> createState() =>
      _WorkOrdersListScreenState();
}

class _WorkOrdersListScreenState extends ConsumerState<WorkOrdersListScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(workOrdersBoardProvider);
    final search = _searchController.text.trim().toLowerCase();

    return AppPageLayout(
      title: 'İş Emirleri',
      subtitle: 'Tüm iş emirlerini listeleyin ve yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.read(workOrdersBoardProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () async {
            await showCreateWorkOrderDialog(context, ref);
            ref.read(workOrdersBoardProvider.notifier).refresh();
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni İş Emri'),
        ),
      ],
      body: boardAsync.when(
        data: (items) {
          int byStatus(String status) =>
              items.where((item) => item.status == status).length;

          final filtered = items.where((item) {
            if (_statusFilter != 'all' && item.status != _statusFilter) {
              return false;
            }
            if (search.isEmpty) return true;
            final haystack = [
              item.id,
              item.title,
              item.customerName ?? '',
              item.branchName ?? '',
            ].join(' ').toLowerCase();
            return haystack.contains(search);
          }).toList(growable: false);

          final dateFormat = DateFormat('dd MMM yyyy', 'tr_TR');
          final timeFormat = DateFormat('HH:mm', 'tr_TR');

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              AppCard(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          labelText: 'Ara',
                          hintText: 'İş emri no, konu, müşteri...',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Durum: Tümü'),
                          ),
                          DropdownMenuItem(
                            value: 'open',
                            child: Text('Durum: Bekleyen'),
                          ),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('Durum: Yapılıyor'),
                          ),
                          DropdownMenuItem(
                            value: 'done',
                            child: Text('Durum: Tamamlandı'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Durum: İptal'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _statusFilter = value ?? 'all'),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.filter_alt_rounded),
                          labelText: 'Durum',
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _statusFilter = 'all');
                      },
                      icon: const Icon(
                        Icons.cleaning_services_rounded,
                        size: 18,
                      ),
                      label: const Text('Filtreleri Temizle'),
                    ),
                  ],
                ),
              ),
              const Gap(14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SummaryCard(
                    title: 'Toplam İş Emri',
                    value: items.length.toString(),
                    icon: Icons.assignment_rounded,
                    tone: AppBadgeTone.primary,
                  ),
                  _SummaryCard(
                    title: 'Bekleyen',
                    value: byStatus('open').toString(),
                    icon: Icons.radio_button_unchecked_rounded,
                    tone: AppBadgeTone.warning,
                  ),
                  _SummaryCard(
                    title: 'Yapılıyor',
                    value: byStatus('in_progress').toString(),
                    icon: Icons.timelapse_rounded,
                    tone: AppBadgeTone.primary,
                  ),
                  _SummaryCard(
                    title: 'Tamamlandı',
                    value: byStatus('done').toString(),
                    icon: Icons.check_circle_rounded,
                    tone: AppBadgeTone.success,
                  ),
                  _SummaryCard(
                    title: 'İptal',
                    value: byStatus('cancelled').toString(),
                    icon: Icons.cancel_rounded,
                    tone: AppBadgeTone.error,
                  ),
                ],
              ),
              const Gap(14),
              AppCard(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Kayıt bulunamadı.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('İş Emri No')),
                            DataColumn(label: Text('Konu')),
                            DataColumn(label: Text('Müşteri / Lokasyon')),
                            DataColumn(label: Text('Planlanan Tarih')),
                            DataColumn(label: Text('Durum')),
                            DataColumn(label: Text('Oluşturulma')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final item in filtered)
                              DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      '#${_shortId(item.id)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primary,
                                          ),
                                    ),
                                  ),
                                  DataCell(Text(item.title)),
                                  DataCell(
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(item.customerName ?? '-'),
                                        if ((item.branchName ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          Text(
                                            item.branchName!.trim(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppTheme.textMuted,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    item.scheduledDate == null
                                        ? const Text('-')
                                        : Text(
                                            '${dateFormat.format(item.scheduledDate!)}\n${timeFormat.format(item.scheduledDate!)}',
                                          ),
                                  ),
                                  DataCell(_statusBadge(item.status)),
                                  DataCell(
                                    item.createdAt == null
                                        ? const Text('-')
                                        : Text(
                                            '${dateFormat.format(item.createdAt!)}\n${timeFormat.format(item.createdAt!)}',
                                          ),
                                  ),
                                  DataCell(
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        await showWorkOrderDetailSheet(
                                          context,
                                          ref,
                                          order: item,
                                        );
                                        ref
                                            .read(
                                              workOrdersBoardProvider.notifier,
                                            )
                                            .refresh();
                                      },
                                      icon: const Icon(
                                        Icons.visibility_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Görüntüle'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => Skeletonizer(
          enabled: true,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              AppCard(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Ara',
                  ),
                ),
              ),
              const Gap(14),
              AppCard(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('İş Emri No')),
                    DataColumn(label: Text('Konu')),
                    DataColumn(label: Text('Müşteri / Lokasyon')),
                    DataColumn(label: Text('Planlanan Tarih')),
                    DataColumn(label: Text('Durum')),
                    DataColumn(label: Text('Oluşturulma')),
                    DataColumn(label: Text('')),
                  ],
                  rows: const [
                    DataRow(
                      cells: [
                        DataCell(Text('#000000')),
                        DataCell(Text('Örnek iş emri')),
                        DataCell(Text('Müşteri')),
                        DataCell(Text('01.01.2026')),
                        DataCell(Text('BEKLEYEN')),
                        DataCell(Text('01.01.2026')),
                        DataCell(Text('Görüntüle')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        error: (_, _) => Center(
          child: AppCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'İş emirleri yüklenemedi. Yetki ve bağlantı ayarlarını kontrol edin.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _shortId(String id) {
    final trimmed = id.trim();
    if (trimmed.length <= 6) return trimmed;
    return trimmed.substring(0, 6);
  }

  static Widget _statusBadge(String status) {
    switch (status) {
      case 'open':
        return const AppBadge(label: 'BEKLEYEN', tone: AppBadgeTone.warning);
      case 'in_progress':
        return const AppBadge(label: 'YAPILIYOR', tone: AppBadgeTone.primary);
      case 'done':
        return const AppBadge(label: 'TAMAMLANDI', tone: AppBadgeTone.success);
      case 'cancelled':
        return const AppBadge(label: 'İPTAL', tone: AppBadgeTone.error);
      default:
        return AppBadge(label: status.toUpperCase(), tone: AppBadgeTone.neutral);
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String value;
  final IconData icon;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(icon, color: AppTheme.primary),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                  const Gap(4),
                  Row(
                    children: [
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const Gap(10),
                      AppBadge(label: value, tone: tone),
                    ],
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
