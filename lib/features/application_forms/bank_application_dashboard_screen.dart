import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'application_form_model.dart';
import 'application_form_screen.dart';

final bankPersonnelNamesProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  final rows = <Map<String, dynamic>>[];

  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'personnel_users'},
    );
    rows.addAll(
      ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>(),
    );
  } else if (client != null) {
    final result = await client
        .from('users')
        .select('id,full_name,role,page_permissions,action_permissions')
        .order('full_name');
    rows.addAll(
      (result as List).map((row) => (row as Map).cast<String, dynamic>()),
    );
  }

  final names = <String, String>{};
  for (final row in rows) {
    if (!_isBankPersonnelRow(row)) continue;
    final id = (row['id'] ?? '').toString().trim();
    final name = (row['full_name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) continue;
    names[id] = name;
  }
  return names;
});

class BankApplicationDashboardScreen extends ConsumerWidget {
  const BankApplicationDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(applicationFormsProvider);
    final personnelNames =
        ref.watch(bankPersonnelNamesProvider).asData?.value ?? const {};
    final profile = ref.watch(currentUserProfileProvider).value;
    final isAdmin = profile?.isBankAdminLike ?? false;

    return AppPageLayout(
      title: 'Capital Bank ÖKC Panel',
      subtitle: isAdmin
          ? 'Tüm banka personelinin talep performansı ve onay durumu.'
          : 'Kendi ÖKC talep performansınız ve onay durumu.',
      compactHeader: true,
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(applicationFormsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        FilledButton.icon(
          onPressed: () => context.go('/formlar/basvuru'),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Talep'),
        ),
      ],
      body: recordsAsync.when(
        data: (records) {
          final visible = bankVisibleApplicationRecords(
            records: records,
            profile: profile,
            isBankUser: profile?.isBankLike ?? false,
          ).where((record) => record.isActive).toList(growable: false);
          final metrics = _BankDashboardMetrics.fromRecords(
            visible,
            personNames: personnelNames,
          );

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(applicationFormsProvider);
              await ref.read(applicationFormsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                _DashboardHero(metrics: metrics, isAdmin: isAdmin),
                const Gap(14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;
                    final left = Column(
                      children: [
                        _VisualStats(metrics: metrics),
                        const Gap(14),
                        _TrendPanel(metrics: metrics),
                      ],
                    );
                    final right = Column(
                      children: [
                        _StatusPanel(metrics: metrics),
                        const Gap(14),
                        _PeoplePanel(metrics: metrics, isAdmin: isAdmin),
                      ],
                    );
                    if (!wide) {
                      return Column(children: [left, const Gap(14), right]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: left),
                        const Gap(14),
                        Expanded(flex: 2, child: right),
                      ],
                    );
                  },
                ),
                const Gap(14),
                _RecentRequests(
                  records: metrics.recent,
                  personNames: personnelNames,
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Banka paneli yüklenemedi.')),
      ),
    );
  }
}

class _BankDashboardMetrics {
  const _BankDashboardMetrics({
    required this.records,
    required this.pending,
    required this.approved,
    required this.today,
    required this.thisWeek,
    required this.withRegistry,
    required this.daily,
    required this.byPerson,
    required this.recent,
  });

  final List<ApplicationFormRecord> records;
  final int pending;
  final int approved;
  final int today;
  final int thisWeek;
  final int withRegistry;
  final List<_DailyPoint> daily;
  final List<_PersonMetric> byPerson;
  final List<ApplicationFormRecord> recent;

  int get total => records.length;
  double get approvalRatio => total == 0 ? 0 : approved / total;

  factory _BankDashboardMetrics.fromRecords(
    List<ApplicationFormRecord> records, {
    required Map<String, String> personNames,
  }) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));
    final sorted = [...records]
      ..sort((a, b) => b.applicationDate.compareTo(a.applicationDate));
    final byDate = <DateTime, int>{};
    for (var i = 13; i >= 0; i--) {
      final day = startOfToday.subtract(Duration(days: i));
      byDate[day] = 0;
    }
    for (final record in records) {
      final day = DateTime(
        record.applicationDate.year,
        record.applicationDate.month,
        record.applicationDate.day,
      );
      if (byDate.containsKey(day)) {
        byDate[day] = byDate[day]! + 1;
      }
    }

    final people = <String, List<ApplicationFormRecord>>{};
    for (final record in records) {
      final key = (record.createdBy ?? '').trim().isEmpty
          ? 'Bilinmeyen'
          : record.createdBy!.trim();
      people.putIfAbsent(key, () => []).add(record);
    }
    final byPerson = people.entries.map((entry) {
      final list = entry.value;
      final sortedList = [...list]
        ..sort((a, b) => b.applicationDate.compareTo(a.applicationDate));
      return _PersonMetric(
        id: entry.key,
        label: personNames[entry.key] ?? _personLabel(entry.key),
        total: list.length,
        pending: list.where((r) => r.isPendingApproval).length,
        approved: list.where((r) => r.isApproved).length,
        today: list
            .where((r) => _sameDay(r.applicationDate, startOfToday))
            .length,
        thisWeek: list.where((r) {
          final day = DateTime(
            r.applicationDate.year,
            r.applicationDate.month,
            r.applicationDate.day,
          );
          return !day.isBefore(startOfWeek);
        }).length,
        withRegistry: list
            .where((r) => (r.stockRegistryNumber ?? '').trim().isNotEmpty)
            .length,
        lastRequest: sortedList.isEmpty
            ? null
            : sortedList.first.applicationDate,
      );
    }).toList()..sort((a, b) => b.total.compareTo(a.total));

    return _BankDashboardMetrics(
      records: sorted,
      pending: records.where((r) => r.isPendingApproval).length,
      approved: records.where((r) => r.isApproved).length,
      today: records
          .where((r) => _sameDay(r.applicationDate, startOfToday))
          .length,
      thisWeek: records.where((r) {
        final day = DateTime(
          r.applicationDate.year,
          r.applicationDate.month,
          r.applicationDate.day,
        );
        return !day.isBefore(startOfWeek);
      }).length,
      withRegistry: records
          .where((r) => (r.stockRegistryNumber ?? '').trim().isNotEmpty)
          .length,
      daily: byDate.entries
          .map((entry) => _DailyPoint(day: entry.key, count: entry.value))
          .toList(growable: false),
      byPerson: byPerson,
      recent: sorted.take(8).toList(growable: false),
    );
  }
}

class _DailyPoint {
  const _DailyPoint({required this.day, required this.count});

  final DateTime day;
  final int count;
}

class _PersonMetric {
  const _PersonMetric({
    required this.id,
    required this.label,
    required this.total,
    required this.pending,
    required this.approved,
    required this.today,
    required this.thisWeek,
    required this.withRegistry,
    required this.lastRequest,
  });

  final String id;
  final String label;
  final int total;
  final int pending;
  final int approved;
  final int today;
  final int thisWeek;
  final int withRegistry;
  final DateTime? lastRequest;
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({required this.metrics, required this.isAdmin});

  final _BankDashboardMetrics metrics;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F8B7A), Color(0xFF2463C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAdmin ? 'Banka ekibi görünümü' : 'Kişisel talep görünümü',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(8),
              Text(
                '${metrics.total} ÖKC talebi',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 26 : 34,
                ),
              ),
              const Gap(8),
              Text(
                'Bugün ${metrics.today}, bu hafta ${metrics.thisWeek} yeni talep girildi.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
            ],
          );
          final visual = SizedBox(
            width: compact ? double.infinity : 240,
            height: 150,
            child: _ApprovalGauge(metrics: metrics, light: true),
          );
          if (compact) {
            return Column(children: [text, const Gap(18), visual]);
          }
          return Row(
            children: [
              Expanded(child: text),
              const Gap(16),
              visual,
            ],
          );
        },
      ),
    );
  }
}

class _VisualStats extends StatelessWidget {
  const _VisualStats({required this.metrics});

  final _BankDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width < 760 ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        _MetricTile(
          'Toplam',
          metrics.total,
          Icons.description_rounded,
          AppTheme.primary,
        ),
        _MetricTile(
          'Bekleyen',
          metrics.pending,
          Icons.pending_actions_rounded,
          AppTheme.warning,
        ),
        _MetricTile(
          'Onaylı',
          metrics.approved,
          Icons.verified_rounded,
          AppTheme.success,
        ),
        _MetricTile(
          'Sicilli',
          metrics.withRegistry,
          Icons.memory_rounded,
          AppTheme.accent,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.label, this.value, this.icon, this.color);

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 26),
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.text,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.metrics});

  final _BankDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final maxY = metrics.daily.fold<int>(
      0,
      (max, p) => p.count > max ? p.count : max,
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '14 Günlük Talep Trendi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Gap(14),
          SizedBox(
            height: 220,
            child: maxY == 0
                ? const Center(child: Text('Bu aralıkta talep yok.'))
                : BarChart(
                    BarChartData(
                      maxY: (maxY + 1).toDouble(),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 ||
                                  index >= metrics.daily.length ||
                                  index.isOdd) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                DateFormat(
                                  'd/M',
                                  'tr_TR',
                                ).format(metrics.daily[index].day),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < metrics.daily.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: metrics.daily[i].count.toDouble(),
                                width: 12,
                                borderRadius: BorderRadius.circular(4),
                                color: i == metrics.daily.length - 1
                                    ? AppTheme.accent
                                    : AppTheme.primary,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.metrics});

  final _BankDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Onay Dağılımı', style: Theme.of(context).textTheme.titleMedium),
          const Gap(12),
          SizedBox(height: 190, child: _ApprovalGauge(metrics: metrics)),
        ],
      ),
    );
  }
}

class _ApprovalGauge extends StatelessWidget {
  const _ApprovalGauge({required this.metrics, this.light = false});

  final _BankDashboardMetrics metrics;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final total = metrics.total;
    if (total == 0) {
      return Center(
        child: Text(
          'Henüz talep yok',
          style: TextStyle(color: light ? Colors.white : AppTheme.textMuted),
        ),
      );
    }
    return PieChart(
      PieChartData(
        centerSpaceRadius: 48,
        sectionsSpace: 3,
        sections: [
          PieChartSectionData(
            value: metrics.approved.toDouble(),
            color: AppTheme.success,
            title: '',
            radius: 34,
          ),
          PieChartSectionData(
            value: metrics.pending.toDouble(),
            color: AppTheme.warning,
            title: '',
            radius: 34,
          ),
        ],
        centerSpaceColor: Colors.transparent,
      ),
    );
  }
}

class _PeoplePanel extends StatelessWidget {
  const _PeoplePanel({required this.metrics, required this.isAdmin});

  final _BankDashboardMetrics metrics;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final people = isAdmin
        ? metrics.byPerson.take(10).toList(growable: false)
        : metrics.byPerson.take(1).toList(growable: false);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAdmin ? 'Banka Personeli' : 'Benim Kayıtlarım',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Gap(4),
          Text(
            isAdmin
                ? 'Personel bazında talep, onay ve son hareket.'
                : 'Kendi talep, onay ve son hareket özetiniz.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          ),
          const Gap(12),
          if (people.isEmpty)
            const Text('Henüz kayıt yok.')
          else
            for (final person in people) ...[
              _PersonRow(
                person: person,
                maxTotal: metrics.byPerson.first.total,
              ),
              const Gap(10),
            ],
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.maxTotal});

  final _PersonMetric person;
  final int maxTotal;

  @override
  Widget build(BuildContext context) {
    final ratio = maxTotal == 0 ? 0.0 : person.total / maxTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                person.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text('${person.total} talep'),
          ],
        ),
        const Gap(6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 9,
            value: ratio.clamp(0, 1),
            backgroundColor: AppTheme.surfaceSoft,
            color: AppTheme.accent,
          ),
        ),
        const Gap(5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _PersonMiniBadge(
              icon: Icons.today_rounded,
              text: 'Bugün ${person.today}',
              color: AppTheme.primary,
            ),
            _PersonMiniBadge(
              icon: Icons.calendar_month_rounded,
              text: 'Hafta ${person.thisWeek}',
              color: AppTheme.accent,
            ),
            _PersonMiniBadge(
              icon: Icons.verified_rounded,
              text: '${person.approved} onaylı',
              color: AppTheme.success,
            ),
            _PersonMiniBadge(
              icon: Icons.pending_actions_rounded,
              text: '${person.pending} bekleyen',
              color: AppTheme.warning,
            ),
            _PersonMiniBadge(
              icon: Icons.memory_rounded,
              text: '${person.withRegistry} sicilli',
              color: AppTheme.textMuted,
            ),
          ],
        ),
        if (person.lastRequest != null) ...[
          const Gap(5),
          Text(
            'Son talep: ${DateFormat('dd MMM yyyy', 'tr_TR').format(person.lastRequest!)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          ),
        ],
      ],
    );
  }
}

class _PersonMiniBadge extends StatelessWidget {
  const _PersonMiniBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const Gap(4),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.text,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRequests extends StatelessWidget {
  const _RecentRequests({required this.records, required this.personNames});

  final List<ApplicationFormRecord> records;
  final Map<String, String> personNames;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Son Talepler', style: Theme.of(context).textTheme.titleMedium),
          const Gap(10),
          if (records.isEmpty)
            const Text('Henüz talep yok.')
          else
            for (final record in records)
              _RecentRow(record: record, personNames: personNames),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record, required this.personNames});

  final ApplicationFormRecord record;
  final Map<String, String> personNames;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: record.isApproved
                  ? AppTheme.success.withValues(alpha: 0.12)
                  : AppTheme.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              record.isApproved
                  ? Icons.verified_rounded
                  : Icons.schedule_rounded,
              color: record.isApproved ? AppTheme.success : AppTheme.warning,
            ),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  [
                    DateFormat(
                      'dd MMM yyyy',
                      'tr_TR',
                    ).format(record.applicationDate),
                    _recentPersonLabel(record, personNames),
                  ].where((item) => item.trim().isNotEmpty).join(' • '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          AppBadge(
            label: record.isApproved ? 'Onaylı' : 'Bekliyor',
            tone: record.isApproved
                ? AppBadgeTone.success
                : AppBadgeTone.warning,
          ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _personLabel(String id) {
  if (id == 'Bilinmeyen') return id;
  final cleaned = id.replaceAll('-', '');
  if (cleaned.length <= 6) return 'Personel $cleaned';
  return 'Personel ${cleaned.substring(cleaned.length - 6).toUpperCase()}';
}

String _recentPersonLabel(
  ApplicationFormRecord record,
  Map<String, String> personNames,
) {
  final createdBy = (record.createdBy ?? '').trim();
  if (createdBy.isEmpty) return '';
  return personNames[createdBy] ?? _personLabel(createdBy);
}

bool _isBankPersonnelRow(Map<String, dynamic> row) {
  final role = (row['role'] ?? '').toString();
  if (role == 'bank') return true;
  if (role != 'personel') return false;

  final pages = _stringList(row['page_permissions']);
  final actions = _stringList(row['action_permissions']);
  return pages.length == 1 &&
      pages.contains(kPageForms) &&
      (actions.isEmpty || actions.contains(kActionBankAdmin));
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return const [];
}
