import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'application_form_model.dart';
import 'application_form_screen.dart';

class BankApplicationReportScreen extends ConsumerStatefulWidget {
  const BankApplicationReportScreen({super.key});

  @override
  ConsumerState<BankApplicationReportScreen> createState() =>
      _BankApplicationReportScreenState();
}

class _BankApplicationReportScreenState
    extends ConsumerState<BankApplicationReportScreen> {
  final _customerController = TextEditingController();
  final _registryController = TextEditingController();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  DateTime? _fromDate;
  DateTime? _toDate;
  String _approvalStatus = 'all';

  @override
  void dispose() {
    _customerController.dispose();
    _registryController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime? currentValue,
    required ValueChanged<DateTime?> onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentValue ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr', 'TR'),
    );
    if (picked == null) return;
    onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(applicationFormsProvider);
    final profile = ref.watch(currentUserProfileProvider).value;

    return AppPageLayout(
      title: 'Capital Bank ÖKC Rapor',
      subtitle: 'ÖKC taleplerini filtreleyin ve satış raporunu görüntüleyin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(applicationFormsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: recordsAsync.when(
        data: (records) {
          final visible = bankVisibleApplicationRecords(
            records: records,
            profile: profile,
            isBankUser: profile?.isBankLike ?? false,
          ).where((record) => record.isActive).toList(growable: false);
          final filtered = _filter(visible);
          final pending = filtered.where((r) => r.isPendingApproval).length;
          final approved = filtered.where((r) => r.isApproved).length;
          final deviceCount = filtered
              .where((r) => (r.stockRegistryNumber ?? '').trim().isNotEmpty)
              .length;

          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _customerController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person_search_rounded),
                          hintText: 'Müşteri ara',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: TextField(
                        controller: _registryController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.confirmation_num_rounded),
                          hintText: 'Sicil / cihaz ara',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: _ReportDateField(
                        label: 'Başlangıç',
                        value: _fromDate,
                        format: _dateFormat,
                        onTap: () => _pickDate(
                          currentValue: _fromDate,
                          onSelected: (value) =>
                              setState(() => _fromDate = value),
                        ),
                        onClear: _fromDate == null
                            ? null
                            : () => setState(() => _fromDate = null),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: _ReportDateField(
                        label: 'Bitiş',
                        value: _toDate,
                        format: _dateFormat,
                        onTap: () => _pickDate(
                          currentValue: _toDate,
                          onSelected: (value) =>
                              setState(() => _toDate = value),
                        ),
                        onClear: _toDate == null
                            ? null
                            : () => setState(() => _toDate = null),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: _approvalStatus,
                        decoration: const InputDecoration(labelText: 'Durum'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Tümü')),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Onay Bekleyen'),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text('Onaylanmış'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _approvalStatus = value ?? 'all'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _customerController.clear();
                          _registryController.clear();
                          _fromDate = null;
                          _toDate = null;
                          _approvalStatus = 'all';
                        });
                      },
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      label: const Text('Temizle'),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ReportStat(
                    label: 'Toplam Talep',
                    value: filtered.length.toString(),
                    icon: Icons.description_rounded,
                  ),
                  _ReportStat(
                    label: 'Onay Bekleyen',
                    value: pending.toString(),
                    icon: Icons.pending_actions_rounded,
                    tone: AppBadgeTone.warning,
                  ),
                  _ReportStat(
                    label: 'Onaylanmış',
                    value: approved.toString(),
                    icon: Icons.verified_rounded,
                    tone: AppBadgeTone.success,
                  ),
                  _ReportStat(
                    label: 'Cihaz/Sicil',
                    value: deviceCount.toString(),
                    icon: Icons.memory_rounded,
                  ),
                ],
              ),
              const Gap(12),
              AppCard(
                padding: EdgeInsets.zero,
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(
                          child: Text('Filtreye uygun talep bulunamadı.'),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: AppTheme.border),
                        itemBuilder: (context, index) {
                          final record = filtered[index];
                          return _ReportRow(record: record);
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Rapor yüklenemedi.')),
      ),
    );
  }

  List<ApplicationFormRecord> _filter(List<ApplicationFormRecord> records) {
    final customer = _normalize(_customerController.text);
    final registry = _normalize(_registryController.text);
    return records
        .where((record) {
          if (customer.isNotEmpty &&
              !_normalize(record.customerName).contains(customer)) {
            return false;
          }
          if (registry.isNotEmpty) {
            final haystack = _normalize(
              '${record.stockRegistryNumber ?? ''} ${record.fileRegistryNumber ?? ''} ${record.brandModel}',
            );
            if (!haystack.contains(registry)) return false;
          }
          if (_approvalStatus != 'all' &&
              record.approvalStatus != _approvalStatus) {
            return false;
          }
          final day = DateTime(
            record.applicationDate.year,
            record.applicationDate.month,
            record.applicationDate.day,
          );
          if (_fromDate != null) {
            final from = DateTime(
              _fromDate!.year,
              _fromDate!.month,
              _fromDate!.day,
            );
            if (day.isBefore(from)) return false;
          }
          if (_toDate != null) {
            final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
            if (day.isAfter(to)) return false;
          }
          return true;
        })
        .toList(growable: false);
  }
}

class _ReportDateField extends StatelessWidget {
  const _ReportDateField({
    required this.label,
    required this.value,
    required this.format,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final DateFormat format;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded)
              : IconButton(
                  tooltip: 'Temizle',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        child: Text(value == null ? 'Tarih seçin' : format.format(value!)),
      ),
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = AppBadgeTone.primary,
  });

  final String label;
  final String value;
  final IconData icon;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.success => AppTheme.success,
      AppBadgeTone.warning => AppTheme.warning,
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.neutral => AppTheme.textMuted,
      AppBadgeTone.primary => AppTheme.primary,
    };
    return SizedBox(
      width: 220,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const Gap(10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.record});

  final ApplicationFormRecord record;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat(
      'dd.MM.yyyy',
      'tr_TR',
    ).format(record.applicationDate);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Gap(4),
                Text(
                  record.brandModel.isEmpty ? '-' : record.brandModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Expanded(child: Text(date)),
          Expanded(child: Text(record.fileRegistryNumber ?? '-')),
          Expanded(child: Text(record.stockRegistryNumber ?? '-')),
          AppBadge(
            label: record.isApproved ? 'Onaylandı' : 'Bekliyor',
            tone: record.isApproved
                ? AppBadgeTone.success
                : AppBadgeTone.warning,
          ),
        ],
      ),
    );
  }
}

String _normalize(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
}
