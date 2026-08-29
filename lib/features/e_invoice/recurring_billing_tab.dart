import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_phosphor_icons.dart';
import '../../core/ui/empty_state_card.dart';
import '../customers/customer_form_dialog.dart';
import '../customers/customer_model.dart';
import '../customers/customer_select_field.dart';
import '../customers/customers_providers.dart';
import '../invoices/invoice_providers.dart';

class RecurringBillingPlan {
  final String id;
  final String customerId;
  final String? customerName;
  final String? customerEmail;
  final String title;
  final String? description;
  final double amount;
  final double taxRate;
  final String currency;
  final int billingDay;
  final String? email;
  final bool isActive;
  final DateTime? lastRunOn;
  final String? lastInvoiceNumber;
  final bool dueToday;
  final String? currentPeriodStatus;
  final String? currentPeriodError;

  const RecurringBillingPlan({
    required this.id,
    required this.customerId,
    this.customerName,
    this.customerEmail,
    required this.title,
    this.description,
    required this.amount,
    this.taxRate = 20,
    this.currency = 'TRY',
    this.billingDay = 1,
    this.email,
    this.isActive = true,
    this.lastRunOn,
    this.lastInvoiceNumber,
    this.dueToday = false,
    this.currentPeriodStatus,
    this.currentPeriodError,
  });

  factory RecurringBillingPlan.fromJson(Map<String, dynamic> json) {
    final customers = json['customers'];
    return RecurringBillingPlan(
      id: json['id'].toString(),
      customerId: json['customer_id']?.toString() ?? '',
      customerName: customers is Map ? customers['name']?.toString() : null,
      customerEmail: customers is Map ? customers['email']?.toString() : null,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      amount: _toDouble(json['amount']),
      taxRate: _toDouble(json['tax_rate'], fallback: 20),
      currency: json['currency']?.toString() ?? 'TRY',
      billingDay: _toInt(json['billing_day'], fallback: 1),
      email: json['email']?.toString(),
      isActive: json['is_active'] != false,
      lastRunOn: DateTime.tryParse(json['last_run_on']?.toString() ?? ''),
      lastInvoiceNumber: json['last_invoice_number']?.toString(),
      dueToday: json['dueToday'] == true,
      currentPeriodStatus: json['current_period_status']?.toString(),
      currentPeriodError: json['current_period_error']?.toString(),
    );
  }

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? fallback;
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }
}

final recurringBillingPlansProvider =
    FutureProvider.autoDispose<List<RecurringBillingPlan>>((ref) async {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return const [];
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'recurring_billing_list'},
      );
      return ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RecurringBillingPlan.fromJson)
          .toList(growable: false);
    });

class RecurringBillingTab extends ConsumerStatefulWidget {
  const RecurringBillingTab({super.key, required this.moneyTry});

  final NumberFormat moneyTry;

  @override
  ConsumerState<RecurringBillingTab> createState() =>
      _RecurringBillingTabState();
}

class _RecurringBillingTabState extends ConsumerState<RecurringBillingTab> {
  bool _busy = false;

  Future<void> _runDue({String? planId, bool force = false}) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'runRecurringBilling',
          'planId': ?planId,
          if (force) 'force': true,
        },
      );
      if (!mounted) return;
      ref.invalidate(recurringBillingPlansProvider);
      ref.invalidate(invoicesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ??
                'Fatura kesildi ve ödeme linki mail gönderildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Çalıştırılamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(RecurringBillingPlan plan) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'setRecurringBillingPlanActive',
          'id': plan.id,
          'isActive': !plan.isActive,
        },
      );
      if (!mounted) return;
      ref.invalidate(recurringBillingPlansProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Güncellenemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor({RecurringBillingPlan? plan}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _RecurringPlanDialog(plan: plan),
    );
    if (saved == true && mounted) {
      ref.invalidate(recurringBillingPlansProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recurringBillingPlansProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tekrarlayan ödemeler',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(4),
              Text(
                'Firma ekleyin, fatura gününü seçin. O gün fatura kesilir ve '
                'ödeme linki mail gider.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
              const Gap(10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _openEditor(),
                    icon: const Icon(AppPhosphorIcons.plus, size: 16),
                    label: const Text('Firma / plan ekle'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _runDue(),
                    icon: const Icon(AppPhosphorIcons.paperPlaneTilt, size: 16),
                    label: const Text('Bugünün faturalarını kes ve mail at'),
                  ),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: () =>
                        ref.invalidate(recurringBillingPlansProvider),
                    icon: const Icon(AppPhosphorIcons.arrowsCounterClockwise),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(10),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyStateCard(
              icon: AppPhosphorIcons.warningCircle,
              title: 'Planlar alınamadı',
              message: '$error',
            ),
            data: (plans) {
              if (plans.isEmpty) {
                return EmptyStateCard(
                  icon: AppPhosphorIcons.calendarCheck,
                  title: 'Henüz plan yok',
                  message:
                      'Tekrarlayan ödeme için firma ekleyin. Seçilen günde '
                      'fatura kesilip ödeme linki mail gider.',
                  action: FilledButton(
                    onPressed: () => _openEditor(),
                    child: const Text('İlk planı ekle'),
                  ),
                );
              }
              return ListView.separated(
                itemCount: plans.length,
                separatorBuilder: (_, _) => const Gap(8),
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  final ranThisPeriod = plan.currentPeriodStatus == 'emailed';
                  return AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.customerName ?? 'Cari',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const Gap(2),
                              Text(
                                plan.title,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppTheme.textMuted),
                              ),
                              const Gap(6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  AppBadge(
                                    dense: true,
                                    label: 'Her ayın ${plan.billingDay}. günü',
                                    tone: AppBadgeTone.primary,
                                  ),
                                  if (!plan.isActive)
                                    const AppBadge(
                                      dense: true,
                                      label: 'Pasif',
                                      tone: AppBadgeTone.neutral,
                                    )
                                  else if (ranThisPeriod)
                                    const AppBadge(
                                      dense: true,
                                      label: 'Bu ay mail gitti',
                                      tone: AppBadgeTone.success,
                                    )
                                  else if (plan.dueToday)
                                    const AppBadge(
                                      dense: true,
                                      label: 'Bugün kesilecek',
                                      tone: AppBadgeTone.warning,
                                    ),
                                  if (plan.lastInvoiceNumber != null &&
                                      plan.lastInvoiceNumber!.isNotEmpty)
                                    AppBadge(
                                      dense: true,
                                      label: 'Son: ${plan.lastInvoiceNumber}',
                                      tone: AppBadgeTone.neutral,
                                    ),
                                ],
                              ),
                              if ((plan.currentPeriodError ?? '').isNotEmpty) ...[
                                const Gap(6),
                                Text(
                                  plan.currentPeriodError!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.error),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Gap(8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.moneyTry.format(plan.amount * (1 + plan.taxRate / 100)),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'KDV hariç ${widget.moneyTry.format(plan.amount)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _runDue(
                                        planId: plan.id,
                                        force: ranThisPeriod,
                                      ),
                              child: Text(
                                ranThisPeriod ? 'Yeniden kes' : 'Şimdi kes ve mail at',
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _openEditor(plan: plan),
                              child: const Text('Düzenle'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _toggleActive(plan),
                              child: Text(plan.isActive ? 'Pasife al' : 'Aktifleştir'),
                            ),
                          ],
                        ),
                      ],
                    ),
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

class _RecurringPlanDialog extends ConsumerStatefulWidget {
  const _RecurringPlanDialog({this.plan});

  final RecurringBillingPlan? plan;

  @override
  ConsumerState<_RecurringPlanDialog> createState() =>
      _RecurringPlanDialogState();
}

class _RecurringPlanDialogState extends ConsumerState<_RecurringPlanDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _email;
  late final TextEditingController _tax;
  String? _customerId;
  int _billingDay = 1;
  String _currency = 'TRY';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _title = TextEditingController(text: plan?.title ?? '');
    _description = TextEditingController(text: plan?.description ?? '');
    _amount = TextEditingController(
      text: plan == null ? '' : plan.amount.toStringAsFixed(2),
    );
    _email = TextEditingController(
      text: plan?.email ?? plan?.customerEmail ?? '',
    );
    _tax = TextEditingController(
      text: (plan?.taxRate ?? 20).toStringAsFixed(0),
    );
    _customerId = plan?.customerId;
    _billingDay = plan?.billingDay ?? DateTime.now().day.clamp(1, 28);
    _currency = plan?.currency ?? 'TRY';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    _email.dispose();
    _tax.dispose();
    super.dispose();
  }

  Future<Customer?> _createCustomer() async {
    final createdId = await showCreateCustomerDialog(context);
    if (createdId == null || !mounted) return null;
    ref.invalidate(customersLookupProvider);
    final refreshed = await ref.read(customersLookupProvider.future);
    for (final customer in refreshed) {
      if (customer.id == createdId) {
        setState(() {
          _customerId = customer.id;
          if (_email.text.trim().isEmpty) {
            _email.text = customer.email ?? '';
          }
          if (_title.text.trim().isEmpty) {
            _title.text = customer.name;
          }
        });
        return customer;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (_customerId == null || _customerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cari seçin.')),
      );
      return;
    }
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan adı yazın.')),
      );
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir tutar yazın.')),
      );
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'upsertRecurringBillingPlan',
          if (widget.plan != null) 'id': widget.plan!.id,
          'customerId': _customerId,
          'title': _title.text.trim(),
          'description': _description.text.trim(),
          'amount': amount,
          'taxRate': double.tryParse(_tax.text.trim()) ?? 20,
          'currency': _currency,
          'billingDay': _billingDay,
          'email': _email.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersLookupProvider);
    return AlertDialog(
      title: Text(widget.plan == null ? 'Tekrarlayan ödeme planı' : 'Planı düzenle'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              customersAsync.when(
                data: (customers) => CustomerSelectField(
                  customers: customers,
                  selectedCustomerId: _customerId,
                  label: 'Firma / cari',
                  onSelected: (customer) {
                    setState(() {
                      _customerId = customer?.id;
                      if (customer != null) {
                        if (_title.text.trim().isEmpty) {
                          _title.text = customer.name;
                        }
                        if (_email.text.trim().isEmpty) {
                          _email.text = customer.email ?? '';
                        }
                      }
                    });
                  },
                  onCreateNew: _createCustomer,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Cari listesi yüklenemedi.'),
              ),
              const Gap(10),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Plan / hizmet adı',
                ),
              ),
              const Gap(10),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Fatura kalemi (isteğe bağlı)',
                ),
              ),
              const Gap(10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Birim tutar (KDV hariç)',
                      ),
                    ),
                  ),
                  const Gap(8),
                  SizedBox(
                    width: 88,
                    child: TextField(
                      controller: _tax,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'KDV %'),
                    ),
                  ),
                ],
              ),
              const Gap(10),
              DropdownButtonFormField<int>(
                key: ValueKey('billing-day-$_billingDay'),
                initialValue: _billingDay,
                decoration: const InputDecoration(
                  labelText: 'Fatura günü (her ay)',
                ),
                items: [
                  for (var day = 1; day <= 31; day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text('Ayın $day. günü'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _billingDay = value);
                },
              ),
              const Gap(10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Mail adresi',
                  helperText: 'Boşsa cari e-postası kullanılır.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
