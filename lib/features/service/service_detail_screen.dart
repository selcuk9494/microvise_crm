import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

final serviceDetailProvider =
    FutureProvider.family<ServiceDetail, String>((ref, serviceId) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final row = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'service_detail', 'serviceId': serviceId},
    );
    if (row.isEmpty) throw Exception('Servis kaydı bulunamadı.');
    return ServiceDetail.fromJson(row);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw Exception('Supabase yapılandırılmamış.');

  final row = await client
      .from('service_records')
      .select(
        'id,title,status,created_at,notes,currency,total_amount,steps,parts,labor,customer_id,work_order_id,customers(name,email)',
      )
      .eq('id', serviceId)
      .maybeSingle();

  if (row == null) throw Exception('Servis kaydı bulunamadı.');
  return ServiceDetail.fromJson(row);
});

class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  ConsumerState<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  bool _closing = false;
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 2.5,
    penColor: const Color(0xFF0F172A),
  );

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(serviceDetailProvider(widget.serviceId));

    return detailAsync.when(
      data: (detail) => AppPageLayout(
        title: 'Servis',
        subtitle: detail.title,
        actions: [
          if (detail.status != 'done')
            FilledButton.icon(
              onPressed: _closing
                  ? null
                  : () async {
                      await _showCloseDialog(context, detail);
                      ref.invalidate(serviceDetailProvider(widget.serviceId));
                    },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Kapat'),
            ),
        ],
        body: _Body(
          detail: detail,
          onChanged: () => ref.invalidate(serviceDetailProvider(widget.serviceId)),
        ),
      ),
      loading: () => const AppPageLayout(
        title: 'Servis',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => AppPageLayout(
        title: 'Servis',
        body: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Servis kaydı yüklenemedi.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCloseDialog(BuildContext context, ServiceDetail detail) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    final payments = [_PaymentDraft()];
    final notesController = TextEditingController(text: detail.notes ?? '');
    final currencyController = ValueNotifier<String>(detail.currency ?? 'TRY');

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
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Servis Kapat',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kapat',
                          onPressed: _closing ? null : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Gap(12),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Signature(
                          controller: _signature,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const Gap(10),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _closing ? null : () => _signature.clear(),
                          child: const Text('Temizle'),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Text(
                            'Müşteri imzası ve ödeme bilgileri.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    ValueListenableBuilder(
                      valueListenable: currencyController,
                      builder: (context, currency, _) => DropdownButtonFormField<String>(
                        initialValue: currency,
                        items: const [
                          DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                        ],
                        onChanged: _closing
                            ? null
                            : (v) => currencyController.value = v ?? 'TRY',
                        decoration: const InputDecoration(labelText: 'Para Birimi'),
                      ),
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ödemeler',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _closing
                              ? null
                              : () => setState(() => payments.add(_PaymentDraft())),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Ekle'),
                        ),
                      ],
                    ),
                    const Gap(10),
                    for (int i = 0; i < payments.length; i++) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: payments[i].amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Tutar',
                                hintText: '0.00',
                              ),
                            ),
                          ),
                          const Gap(10),
                          if (payments.length > 1)
                            IconButton(
                              tooltip: 'Sil',
                              onPressed: _closing
                                  ? null
                                  : () => setState(() {
                                        payments[i].dispose();
                                        payments.removeAt(i);
                                      }),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                        ],
                      ),
                      if (i != payments.length - 1) const Gap(10),
                    ],
                    const Gap(12),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Not',
                        hintText: 'İsteğe bağlı',
                      ),
                    ),
                    const Gap(18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _closing ? null : () => Navigator.of(context).pop(),
                            child: const Text('Vazgeç'),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _closing
                                ? null
                                : () async {
                                    setState(() => _closing = true);
                                    try {
                                      final now = DateTime.now();
                                      final sig = await _signature.toPngBytes();
                                      final sigUrl = sig == null || sig.isEmpty
                                          ? null
                                          : 'data:image/png;base64,${base64Encode(sig)}';

                                      final total = detail.totalAmount ?? 0;
                                      await client.from('service_records').update({
                                        'status': 'done',
                                        'notes': notesController.text.trim().isEmpty
                                            ? null
                                            : notesController.text.trim(),
                                        'currency': currencyController.value,
                                        'total_amount': total,
                                        'signature_url': sigUrl,
                                      }).eq('id', detail.id);

                                      final paymentRows = <Map<String, dynamic>>[];
                                      for (final p in payments) {
                                        final amount = p.amount;
                                        if (amount == null) continue;
                                        paymentRows.add({
                                          'customer_id': detail.customerId,
                                          'work_order_id': detail.workOrderId,
                                          'amount': amount,
                                          'currency': currencyController.value,
                                          'paid_at': now.toIso8601String(),
                                          'created_by': client.auth.currentUser?.id,
                                          'is_active': true,
                                        });
                                      }
                                      if (paymentRows.isNotEmpty) {
                                        await client.from('payments').insert(paymentRows);
                                      }

                                      final email = detail.customerEmail;
                                      if (email != null &&
                                          email.trim().isNotEmpty &&
                                          sigUrl != null) {
                                        try {
                                          await client.functions.invoke(
                                            'send_work_order_closed_email',
                                            body: {
                                              'to': email,
                                              'customerName': detail.customerName ?? '',
                                              'workOrderTitle': detail.title,
                                              'signatureDataUrl': sigUrl,
                                            },
                                          );
                                        } catch (_) {}
                                      }

                                      if (!context.mounted) return;
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Servis kapatıldı.')),
                                      );
                                    } on AuthException catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Hata: ${e.message}')),
                                      );
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Servis kapatılamadı.')),
                                      );
                                    } finally {
                                      setState(() => _closing = false);
                                    }
                                  },
                            child: _closing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Kapat'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    notesController.dispose();
    currencyController.dispose();
    for (final p in payments) {
      p.dispose();
    }
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.detail, required this.onChanged});

  final ServiceDetail detail;
  final VoidCallback onChanged;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late List<String> _steps;
  late List<_LineItemDraft> _parts;
  late List<_LineItemDraft> _labor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _steps = [...widget.detail.steps];
    _parts = widget.detail.parts.map(_LineItemDraft.from).toList();
    _labor = widget.detail.labor.map(_LineItemDraft.from).toList();
  }

  double get _total {
    double sum = 0;
    for (final p in _parts) {
      sum += p.total;
    }
    for (final l in _labor) {
      sum += l.total;
    }
    return sum;
  }

  Future<void> _save() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      await client.from('service_records').update({
        'steps': _steps,
        'parts': _parts.map((e) => e.toJson()).toList(),
        'labor': _labor.map((e) => e.toJson()).toList(),
        'total_amount': _total,
      }).eq('id', widget.detail.id);

      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedildi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM y', 'tr_TR').format(widget.detail.createdAt);
    final tone = widget.detail.status == 'done'
        ? AppBadgeTone.success
        : widget.detail.status == 'in_progress'
            ? AppBadgeTone.primary
            : AppBadgeTone.warning;
    final label = widget.detail.status == 'done'
        ? 'Tamam'
        : widget.detail.status == 'in_progress'
            ? 'Devam'
            : 'Açık';

    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.detail.customerName ?? '—',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  AppBadge(label: label, tone: tone),
                ],
              ),
              const Gap(6),
              Text(
                date,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const Gap(12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Adımlar', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _steps.add('Yeni adım')),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
              const Gap(10),
              for (int i = 0; i < _steps.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                        ),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _steps[i]),
                        onChanged: (v) => _steps[i] = v,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama',
                        ),
                      ),
                    ),
                    const Gap(10),
                    IconButton(
                      tooltip: 'Sil',
                      onPressed: _saving ? null : () => setState(() => _steps.removeAt(i)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                if (i != _steps.length - 1) const Gap(10),
              ],
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(12),
        _CostCard(
          title: 'Parçalar',
          items: _parts,
          onAdd: _saving ? null : () => setState(() => _parts.add(_LineItemDraft.empty())),
          onRemove: _saving
              ? null
              : (i) => setState(() {
                    _parts[i].dispose();
                    _parts.removeAt(i);
                  }),
        ),
        const Gap(12),
        _CostCard(
          title: 'İşçilik',
          items: _labor,
          onAdd: _saving ? null : () => setState(() => _labor.add(_LineItemDraft.empty())),
          onRemove: _saving
              ? null
              : (i) => setState(() {
                    _labor[i].dispose();
                    _labor.removeAt(i);
                  }),
        ),
        const Gap(12),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Toplam',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2)
                    .format(_total),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CostCard extends StatelessWidget {
  const _CostCard({
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<_LineItemDraft> items;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(10),
          if (items.isEmpty)
            Text(
              'Kayıt yok.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFF64748B)),
            )
          else
            for (int i = 0; i < items.length; i++) ...[
              _LineItemEditor(
                item: items[i],
                onRemove: onRemove == null ? null : () => onRemove!(i),
              ),
              if (i != items.length - 1) const Gap(10),
            ],
        ],
      ),
    );
  }
}

class _LineItemEditor extends StatelessWidget {
  const _LineItemEditor({required this.item, required this.onRemove});

  final _LineItemDraft item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            controller: item.nameController,
            decoration: const InputDecoration(labelText: 'Kalem'),
          ),
        ),
        const Gap(10),
        Expanded(
          flex: 2,
          child: TextField(
            controller: item.qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Adet/Saat'),
          ),
        ),
        const Gap(10),
        Expanded(
          flex: 3,
          child: TextField(
            controller: item.unitPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Birim Fiyat'),
          ),
        ),
        const Gap(10),
        if (onRemove != null)
          IconButton(
            tooltip: 'Sil',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    );
  }
}

class _LineItemDraft {
  _LineItemDraft({
    required this.nameController,
    required this.qtyController,
    required this.unitPriceController,
  });

  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController unitPriceController;

  factory _LineItemDraft.empty() => _LineItemDraft(
        nameController: TextEditingController(),
        qtyController: TextEditingController(text: '1'),
        unitPriceController: TextEditingController(text: '0'),
      );

  factory _LineItemDraft.from(Map<String, dynamic> json) {
    return _LineItemDraft(
      nameController: TextEditingController(text: json['name']?.toString() ?? ''),
      qtyController: TextEditingController(text: json['qty']?.toString() ?? '1'),
      unitPriceController:
          TextEditingController(text: json['unit_price']?.toString() ?? '0'),
    );
  }

  double get qty => double.tryParse(qtyController.text.trim().replaceAll(',', '.')) ?? 0;
  double get unitPrice =>
      double.tryParse(unitPriceController.text.trim().replaceAll(',', '.')) ?? 0;
  double get total => qty * unitPrice;

  Map<String, dynamic> toJson() {
    return {
      'name': nameController.text.trim(),
      'qty': qty,
      'unit_price': unitPrice,
    };
  }

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    unitPriceController.dispose();
  }
}

class _PaymentDraft {
  _PaymentDraft();

  final amountController = TextEditingController();

  double? get amount {
    final raw = amountController.text.trim().replaceAll(',', '.');
    return double.tryParse(raw);
  }

  void dispose() => amountController.dispose();
}

class ServiceDetail {
  const ServiceDetail({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.notes,
    required this.currency,
    required this.totalAmount,
    required this.steps,
    required this.parts,
    required this.labor,
    required this.customerId,
    required this.workOrderId,
    required this.customerName,
    required this.customerEmail,
  });

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final String? notes;
  final String? currency;
  final double? totalAmount;
  final List<String> steps;
  final List<Map<String, dynamic>> parts;
  final List<Map<String, dynamic>> labor;
  final String? customerId;
  final String? workOrderId;
  final String? customerName;
  final String? customerEmail;

  factory ServiceDetail.fromJson(Map<String, dynamic> json) {
    final customers = json['customers'] as Map<String, dynamic>?;
    final stepsRaw = json['steps'];
    final partsRaw = json['parts'];
    final laborRaw = json['labor'];

    return ServiceDetail(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      notes: json['notes']?.toString(),
      currency: json['currency']?.toString(),
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      steps: (stepsRaw is List)
          ? stepsRaw.map((e) => e.toString()).toList()
          : const [],
      parts: (partsRaw is List)
          ? partsRaw.map((e) => (e as Map).cast<String, dynamic>()).toList()
          : const [],
      labor: (laborRaw is List)
          ? laborRaw.map((e) => (e as Map).cast<String, dynamic>()).toList()
          : const [],
      customerId: json['customer_id']?.toString(),
      workOrderId: json['work_order_id']?.toString(),
      customerName: customers?['name']?.toString(),
      customerEmail: customers?['email']?.toString(),
    );
  }
}
