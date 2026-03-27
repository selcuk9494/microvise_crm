import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../customers/customer_detail_screen.dart';
import 'work_order_model.dart';

Future<void> showWorkOrderCloseSheet(
  BuildContext context,
  WidgetRef ref, {
  required WorkOrder order,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _WorkOrderCloseSheet(order: order),
  );
}

class _WorkOrderCloseSheet extends ConsumerStatefulWidget {
  const _WorkOrderCloseSheet({required this.order});

  final WorkOrder order;

  @override
  ConsumerState<_WorkOrderCloseSheet> createState() =>
      _WorkOrderCloseSheetState();
}

class _WorkOrderCloseSheetState extends ConsumerState<_WorkOrderCloseSheet> {
  final _notesController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _addressController = TextEditingController();

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: const Color(0xFF0F172A),
  );

  bool _saving = false;
  bool _addLine = false;
  bool _addGmp3 = false;

  final _lineNumberController = TextEditingController();
  final _lineSimController = TextEditingController();

  final _gmp3NameController = TextEditingController(text: 'GMP3 Lisansı');

  String? _selectedBranchId;
  final List<_PaymentDraft> _payments = [_PaymentDraft()];

  @override
  void dispose() {
    _notesController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _addressController.dispose();
    _signatureController.dispose();
    _lineNumberController.dispose();
    _lineSimController.dispose();
    _gmp3NameController.dispose();
    for (final p in _payments) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _save(CustomerDetail customer) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();

      final branchId = _selectedBranchId ?? widget.order.branchId;
      if (branchId != null) {
        final lat = double.tryParse(_latController.text.trim());
        final lng = double.tryParse(_lngController.text.trim());
        final address = _addressController.text.trim();
        final latMap = lat == null ? null : {'location_lat': lat};
        final lngMap = lng == null ? null : {'location_lng': lng};
        final addressMap = address.isEmpty ? null : {'address': address};

        if (lat != null || lng != null || address.isNotEmpty) {
          await client
              .from('branches')
              .update({...?latMap, ...?lngMap, ...?addressMap})
              .eq('id', branchId);
        }
      }

      if (_addLine) {
        final number = _lineNumberController.text.trim();
        if (number.isEmpty) {
          throw Exception('Hat numarası gerekli.');
        }

        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, 12, 31);
        await client.from('lines').insert({
          'customer_id': customer.id,
          'branch_id': branchId,
          'number': number,
          'sim_number': _lineSimController.text.trim().isEmpty
              ? null
              : _lineSimController.text.trim(),
          'starts_at': start.toIso8601String().substring(0, 10),
          'ends_at': end.toIso8601String().substring(0, 10),
          'expires_at': end.toIso8601String().substring(0, 10),
          'is_active': true,
        });
      }

      if (_addGmp3) {
        final name = _gmp3NameController.text.trim();
        if (name.isEmpty) throw Exception('GMP3 adı gerekli.');
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, 12, 31);
        await client.from('licenses').insert({
          'customer_id': customer.id,
          'name': name,
          'license_type': 'gmp3',
          'starts_at': start.toIso8601String().substring(0, 10),
          'ends_at': end.toIso8601String().substring(0, 10),
          'expires_at': end.toIso8601String().substring(0, 10),
          'is_active': true,
        });
      }

      final paymentRows = <Map<String, dynamic>>[];
      for (final p in _payments) {
        final amount = p.amount;
        if (amount == null) continue;
        paymentRows.add({
          'customer_id': customer.id,
          'work_order_id': widget.order.id,
          'amount': amount,
          'currency': p.currency,
          'description': p.description,
          'paid_at': now.toIso8601String(),
          'created_by': client.auth.currentUser?.id,
          'is_active': true,
        });
      }
      if (paymentRows.isNotEmpty) {
        await client.from('payments').insert(paymentRows);
      }

      Uint8List? signatureBytes = await _signatureController.toPngBytes();
      String? signatureDataUrl;
      if (signatureBytes != null && signatureBytes.isNotEmpty) {
        signatureDataUrl =
            'data:image/png;base64,${base64Encode(signatureBytes)}';
      }

      await client
          .from('work_orders')
          .update({
            'status': 'done',
            'branch_id': branchId,
            'closed_at': now.toIso8601String(),
            'closed_by': client.auth.currentUser?.id,
            'close_notes': _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          })
          .eq('id', widget.order.id);

      if (customer.email != null &&
          customer.email!.trim().isNotEmpty &&
          signatureDataUrl != null) {
        try {
          await client.functions.invoke(
            'send_work_order_closed_email',
            body: {
              'to': customer.email,
              'customerName': customer.name,
              'workOrderTitle': widget.order.title,
              'signatureDataUrl': signatureDataUrl,
            },
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('İmza kaydedildi; e-posta gönderilemedi.'),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İş emri kapatıldı.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(
      customerDetailProvider(widget.order.customerId),
    );
    final branchesAsync = ref.watch(
      customerBranchesProvider(widget.order.customerId),
    );

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: customerAsync.when(
            data: (customer) => _SheetBody(
              order: widget.order,
              customer: customer,
              branchesAsync: branchesAsync,
              selectedBranchId: _selectedBranchId ?? widget.order.branchId,
              onBranchChanged: _saving
                  ? null
                  : (id) => setState(() => _selectedBranchId = id),
              notesController: _notesController,
              addressController: _addressController,
              latController: _latController,
              lngController: _lngController,
              addLine: _addLine,
              addGmp3: _addGmp3,
              onToggleAddLine: _saving
                  ? null
                  : (v) => setState(() => _addLine = v),
              onToggleAddGmp3: _saving
                  ? null
                  : (v) => setState(() => _addGmp3 = v),
              lineNumberController: _lineNumberController,
              lineSimController: _lineSimController,
              gmp3NameController: _gmp3NameController,
              signatureController: _signatureController,
              payments: _payments,
              saving: _saving,
              onAddPayment: _saving
                  ? null
                  : () => setState(() => _payments.add(_PaymentDraft())),
              onRemovePayment: _saving
                  ? null
                  : (index) => setState(() {
                      _payments[index].dispose();
                      _payments.removeAt(index);
                    }),
              onSave: () => _save(customer),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Padding(
              padding: const EdgeInsets.all(18),
              child: AppCard(
                child: Text(
                  'Müşteri bilgisi yüklenemedi.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.order,
    required this.customer,
    required this.branchesAsync,
    required this.selectedBranchId,
    required this.onBranchChanged,
    required this.notesController,
    required this.addressController,
    required this.latController,
    required this.lngController,
    required this.addLine,
    required this.addGmp3,
    required this.onToggleAddLine,
    required this.onToggleAddGmp3,
    required this.lineNumberController,
    required this.lineSimController,
    required this.gmp3NameController,
    required this.signatureController,
    required this.payments,
    required this.saving,
    required this.onAddPayment,
    required this.onRemovePayment,
    required this.onSave,
  });

  final WorkOrder order;
  final CustomerDetail customer;
  final AsyncValue<List<CustomerBranch>> branchesAsync;
  final String? selectedBranchId;
  final ValueChanged<String?>? onBranchChanged;
  final TextEditingController notesController;
  final TextEditingController addressController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final bool addLine;
  final bool addGmp3;
  final ValueChanged<bool>? onToggleAddLine;
  final ValueChanged<bool>? onToggleAddGmp3;
  final TextEditingController lineNumberController;
  final TextEditingController lineSimController;
  final TextEditingController gmp3NameController;
  final SignatureController signatureController;
  final List<_PaymentDraft> payments;
  final bool saving;
  final VoidCallback? onAddPayment;
  final ValueChanged<int>? onRemovePayment;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '',
      decimalDigits: 2,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const Gap(14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'İş Emri Kapat',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(2),
                  Text(
                    '${customer.name} • ${order.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            AppBadge(label: 'Tamamla', tone: AppBadgeTone.success),
          ],
        ),
        const Gap(14),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Şube & Konum',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(10),
                    branchesAsync.when(
                      data: (branches) => DropdownButtonFormField<String?>(
                        initialValue: selectedBranchId,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Şube seç'),
                          ),
                          ...branches.map(
                            (b) => DropdownMenuItem<String?>(
                              value: b.id,
                              child: Text(b.name),
                            ),
                          ),
                        ],
                        onChanged: onBranchChanged,
                        decoration: const InputDecoration(labelText: 'Şube'),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (error, stackTrace) => const SizedBox.shrink(),
                    ),
                    const Gap(12),
                    TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Adres (güncelle)',
                        hintText: 'Cadde, sokak, no, ilçe...',
                      ),
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Konum Lat',
                              hintText: '41.0',
                            ),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: TextField(
                            controller: lngController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Konum Lng',
                              hintText: '29.0',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(12),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ödemeler',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onAddPayment,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Ödeme Ekle'),
                        ),
                      ],
                    ),
                    const Gap(10),
                    for (int i = 0; i < payments.length; i++) ...[
                      _PaymentRow(
                        draft: payments[i],
                        canRemove: payments.length > 1,
                        onRemove: onRemovePayment == null
                            ? null
                            : () => onRemovePayment!(i),
                        money: money,
                      ),
                      if (i != payments.length - 1) const Gap(10),
                    ],
                  ],
                ),
              ),
              const Gap(12),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('İmza', style: Theme.of(context).textTheme.titleSmall),
                    const Gap(10),
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
                          controller: signatureController,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const Gap(10),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => signatureController.clear(),
                          child: const Text('Temizle'),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Text(
                            customer.email?.trim().isNotEmpty ?? false
                                ? 'İmza ile birlikte e-posta gönderimi denenecek.'
                                : 'E-posta yoksa gönderim yapılmaz.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(12),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ek Satış (opsiyonel)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: addLine,
                      onChanged: onToggleAddLine,
                      title: const Text('Hat Satışı Ekle'),
                      subtitle: const Text(
                        'Başlangıç: bugün • Bitiş: yıl sonu',
                      ),
                    ),
                    if (addLine) ...[
                      const Gap(10),
                      TextField(
                        controller: lineNumberController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Hat Numarası',
                          hintText: '90555...',
                        ),
                      ),
                      const Gap(10),
                      TextField(
                        controller: lineSimController,
                        decoration: const InputDecoration(
                          labelText: 'SIM Numarası',
                          hintText: '89...',
                        ),
                      ),
                    ],
                    const Divider(height: 24),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: addGmp3,
                      onChanged: onToggleAddGmp3,
                      title: const Text('GMP3 Lisansı Sat'),
                      subtitle: const Text(
                        'Başlangıç: bugün • Bitiş: yıl sonu',
                      ),
                    ),
                    if (addGmp3) ...[
                      const Gap(10),
                      TextField(
                        controller: gmp3NameController,
                        decoration: const InputDecoration(
                          labelText: 'Lisans Adı',
                          hintText: 'GMP3 Lisansı',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(12),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kapanış Açıklaması',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(10),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama',
                        hintText: 'İş emri kapanışına dair açıklama girin',
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(16),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Vazgeç'),
              ),
            ),
            const Gap(12),
            Expanded(
              child: FilledButton(
                onPressed: saving ? null : onSave,
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('İş Emrini Kapat'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PaymentDraft {
  _PaymentDraft();

  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  String currency = 'TRY';

  double? get amount {
    final raw = amountController.text.trim().replaceAll(',', '.');
    return double.tryParse(raw);
  }

  String? get description {
    final value = descriptionController.text.trim();
    return value.isEmpty ? null : value;
  }

  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
  }
}

class _PaymentRow extends StatefulWidget {
  const _PaymentRow({
    required this.draft,
    required this.canRemove,
    required this.onRemove,
    required this.money,
  });

  final _PaymentDraft draft;
  final bool canRemove;
  final VoidCallback? onRemove;
  final NumberFormat money;

  @override
  State<_PaymentRow> createState() => _PaymentRowState();
}

class _PaymentRowState extends State<_PaymentRow> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              TextField(
                controller: widget.draft.amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tutar',
                  hintText: '0.00',
                ),
                onChanged: (value) => setState(() {}),
              ),
              const Gap(8),
              TextField(
                controller: widget.draft.descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Örn: Kurulum tahsilatı',
                ),
              ),
            ],
          ),
        ),
        const Gap(10),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: widget.draft.currency,
            items: const [
              DropdownMenuItem(value: 'TRY', child: Text('TRY')),
              DropdownMenuItem(value: 'USD', child: Text('USD')),
              DropdownMenuItem(value: 'EUR', child: Text('EUR')),
              DropdownMenuItem(value: 'GBP', child: Text('GBP (STG)')),
            ],
            onChanged: (v) =>
                setState(() => widget.draft.currency = v ?? 'TRY'),
            decoration: const InputDecoration(labelText: 'Para Birimi'),
          ),
        ),
        const Gap(10),
        if (widget.canRemove)
          IconButton(
            tooltip: 'Sil',
            onPressed: widget.onRemove,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    );
  }
}
