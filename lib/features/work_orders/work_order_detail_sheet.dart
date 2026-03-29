import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../../app/theme/app_theme.dart';
import '../billing/invoice_queue_helper.dart';
import '../../core/platform/open_external_url.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/compact_stat_card.dart';
import '../customers/customer_detail_screen.dart';
import 'work_order_create_dialog.dart';
import 'work_order_model.dart';
import 'currency_service.dart';

Future<void> showWorkOrderDetailSheet(
  BuildContext context,
  WidgetRef ref, {
  required WorkOrder order,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _WorkOrderDetailSheet(order: order),
  );
}

class _WorkOrderDetailSheet extends ConsumerStatefulWidget {
  const _WorkOrderDetailSheet({required this.order});

  final WorkOrder order;

  @override
  ConsumerState<_WorkOrderDetailSheet> createState() =>
      _WorkOrderDetailSheetState();
}

class _WorkOrderDetailSheetState extends ConsumerState<_WorkOrderDetailSheet> {
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
  bool _isClosing = false;

  final _lineNumberController = TextEditingController();
  final _lineSimController = TextEditingController();

  final _gmp3NameController = TextEditingController(text: 'GMP3 Lisansı');

  String? _selectedBranchId;
  final List<_PaymentDraft> _payments = [];

  Map<String, double> _exchangeRates = {};
  bool _loadingRates = false;

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.order.address ?? '';
    _loadExchangeRates();
  }

  Future<void> _loadExchangeRates() async {
    setState(() => _loadingRates = true);
    try {
      _exchangeRates = await CurrencyService.getExchangeRates();
    } catch (_) {
      _exchangeRates = {'USD': 34.50, 'EUR': 37.20, 'GBP': 43.80};
    }
    if (mounted) setState(() => _loadingRates = false);
  }

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

  Future<void> _updateStatus(String newStatus) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      await client
          .from('work_orders')
          .update({'status': newStatus})
          .eq('id', widget.order.id);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İş emri durumu güncellendi.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Durum güncellenemedi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeWorkOrder(CustomerDetail customer) async {
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
        final insertedLine = await client
            .from('lines')
            .insert({
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
            })
            .select('id')
            .single();
        await enqueueInvoiceItem(
          client,
          itemType: 'line_activation',
          sourceTable: 'lines',
          sourceId: insertedLine['id'].toString(),
          customerId: customer.id,
          description: 'Hat Aktivasyonu - ${customer.name} / $number',
          sourceEvent: 'line_activated',
          sourceLabel: 'Hat Aktivasyonu',
        );
      }

      if (_addGmp3) {
        final name = _gmp3NameController.text.trim();
        if (name.isEmpty) throw Exception('GMP3 adı gerekli.');
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, 12, 31);
        final insertedLicense = await client
            .from('licenses')
            .insert({
              'customer_id': customer.id,
              'name': name,
              'license_type': 'gmp3',
              'starts_at': start.toIso8601String().substring(0, 10),
              'ends_at': end.toIso8601String().substring(0, 10),
              'expires_at': end.toIso8601String().substring(0, 10),
              'is_active': true,
            })
            .select('id')
            .single();
        await enqueueInvoiceItem(
          client,
          itemType: 'gmp3_activation',
          sourceTable: 'licenses',
          sourceId: insertedLicense['id'].toString(),
          customerId: customer.id,
          description: 'GMP3 Aktivasyonu - ${customer.name} / $name',
          sourceEvent: 'gmp3_activated',
          sourceLabel: 'GMP3 Aktivasyonu',
        );
      }

      for (final p in _payments) {
        final amount = p.amount;
        if (amount == null) continue;
        final paymentPayload = <String, dynamic>{
          'customer_id': customer.id,
          'work_order_id': widget.order.id,
          'amount': amount,
          'currency': p.currency,
          'payment_method': p.method,
          'description': p.description,
          'paid_at': now.toIso8601String(),
          'created_by': client.auth.currentUser?.id,
          'is_active': true,
        };
        Map<String, dynamic> insertedPayment;
        try {
          insertedPayment = await client
              .from('payments')
              .insert(paymentPayload)
              .select('id')
              .single();
        } catch (e) {
          final message = e.toString();
          if (!message.contains("'description' column") &&
              !message.contains("'payment_method' column")) {
            rethrow;
          }
          final fallback = Map<String, dynamic>.from(paymentPayload);
          if (message.contains("'description' column")) {
            fallback.remove('description');
          }
          if (message.contains("'payment_method' column")) {
            fallback.remove('payment_method');
          }
          insertedPayment = await client
              .from('payments')
              .insert(fallback)
              .select('id')
              .single();
        }
        final paymentLabel = p.description == null || p.description!.isEmpty
            ? 'İş Emri Ödemesi'
            : 'İş Emri Ödemesi - ${p.description}';
        await enqueueInvoiceItem(
          client,
          itemType: 'work_order_payment',
          sourceTable: 'payments',
          sourceId: insertedPayment['id'].toString(),
          customerId: customer.id,
          description: '$paymentLabel / ${customer.name}',
          amount: amount,
          currency: p.currency,
          sourceEvent: 'work_order_payment_added',
          sourceLabel: 'İş Emri Ödemesi',
        );
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
    final isDone = widget.order.status == 'done';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.94,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            top: 12,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
          ),
          child: customerAsync.when(
            data: (customer) => Column(
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
                const Gap(12),
                _buildHeader(context, customer),
                const Gap(10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _buildInfoCard(context, customer, branchesAsync),
                      const Gap(10),
                      if (!isDone && !_isClosing) ...[
                        _buildStatusActions(context),
                        const Gap(10),
                      ],
                      if (_isClosing || isDone) ...[
                        _buildPaymentsCard(context),
                        const Gap(10),
                        if (!isDone) ...[
                          _buildSignatureCard(context, customer),
                          const Gap(10),
                          _buildBranchLocationCard(context, branchesAsync),
                          const Gap(10),
                          _buildAdditionalSalesCard(context),
                          const Gap(10),
                          _buildNotesCard(context),
                          const Gap(10),
                        ],
                      ],
                    ],
                  ),
                ),
                if (!isDone) _buildActionButtons(context, customer),
              ],
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

  Widget _buildHeader(BuildContext context, CustomerDetail customer) {
    final (statusLabel, statusTone) = switch (widget.order.status) {
      'open' => ('Açık', AppBadgeTone.warning),
      'in_progress' => ('Devam Ediyor', AppBadgeTone.primary),
      'done' => ('Kapalı', AppBadgeTone.success),
      _ => ('Bilinmiyor', AppBadgeTone.neutral),
    };
    final dateText = widget.order.scheduledDate != null
        ? DateFormat('d MMM', 'tr_TR').format(widget.order.scheduledDate!)
        : 'Tarihsiz';

    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE0E7FF), Color(0xFFDBEAFE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Icon(
                  Icons.assignment_turned_in_rounded,
                  size: 22,
                  color: AppTheme.primary,
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.order.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Gap(6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppBadge(label: statusLabel, tone: statusTone),
                        _HeaderMetaChip(
                          icon: Icons.business_rounded,
                          label: customer.name,
                        ),
                        if (widget.order.workOrderTypeName?.trim().isNotEmpty ??
                            false)
                          _HeaderMetaChip(
                            icon: Icons.category_rounded,
                            label: widget.order.workOrderTypeName!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(14),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                CompactStatCard(
                  label: 'Plan',
                  value: dateText,
                  icon: Icons.event_rounded,
                  color: AppTheme.primary,
                ),
                CompactStatCard(
                  label: 'Ödeme',
                  value: '${_payments.length}',
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF22C55E),
                ),
                CompactStatCard(
                  label: 'Şehir',
                  value: (widget.order.city?.trim().isNotEmpty ?? false)
                      ? widget.order.city!
                      : 'Belirsiz',
                  icon: Icons.location_on_rounded,
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    CustomerDetail customer,
    AsyncValue<List<CustomerBranch>> branchesAsync,
  ) {
    final dateText = widget.order.scheduledDate != null
        ? DateFormat('d MMMM y', 'tr_TR').format(widget.order.scheduledDate!)
        : 'Tarih belirlenmedi';
    CustomerBranch? selectedBranch;
    final selectedBranchId = widget.order.branchId ?? _selectedBranchId;
    final branchItems = branchesAsync.asData?.value ?? const <CustomerBranch>[];
    for (final branch in branchItems) {
      if (branch.id == selectedBranchId) {
        selectedBranch = branch;
        break;
      }
    }
    final directionsUrl = _buildDirectionsUrl(selectedBranch);

    return AppSectionCard(
      title: 'İş Emri Detayları',
      subtitle: 'Operasyon ve iletişim bilgileri',
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            icon: Icons.business_rounded,
            label: 'Müşteri',
            value: customer.name,
          ),
          if (widget.order.workOrderTypeName?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.category_rounded,
              label: 'İş Emri Tipi',
              value: widget.order.workOrderTypeName!,
            ),
          ],
          if (widget.order.address?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.place_rounded,
              label: 'Adres',
              value: widget.order.address!,
            ),
          ],
          if (selectedBranch != null) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.account_tree_rounded,
              label: 'Şube',
              value: selectedBranch.name,
            ),
          ],
          const Gap(8),
          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Planlanan Tarih',
            value: dateText,
          ),
          if (widget.order.description?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.notes_rounded,
              label: 'Açıklama',
              value: widget.order.description!,
            ),
          ],
          if (customer.email?.isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.email_rounded,
              label: 'E-posta',
              value: customer.email!,
            ),
          ],
          if (customer.phone1?.isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.phone_rounded,
              label: 'Telefon',
              value: customer.phone1!,
            ),
          ],
          if (widget.order.contactPhone?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.phone_in_talk_rounded,
              label: 'İrtibat Numarası',
              value: widget.order.contactPhone!,
              valueStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (widget.order.locationLink?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.link_rounded,
              label: 'Konum Linki',
              value: widget.order.locationLink!,
            ),
          ],
          if (selectedBranch?.address?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.location_on_rounded,
              label: 'Şube Adresi',
              value: selectedBranch!.address!,
            ),
          ],
          if (selectedBranch?.phone?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.call_rounded,
              label: 'Şube Telefonu',
              value: selectedBranch!.phone!,
            ),
          ],
          if (widget.order.closeNotes?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.task_alt_rounded,
              label: 'Kapanış Açıklaması',
              value: widget.order.closeNotes!,
            ),
          ],
          if (directionsUrl != null) ...[
            const Gap(12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openDirections(context, directionsUrl),
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('Adres Tarifi Al'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _buildDirectionsUrl(CustomerBranch? selectedBranch) {
    final locationLink = widget.order.locationLink?.trim();
    if (locationLink != null && locationLink.isNotEmpty) {
      return locationLink;
    }
    if (selectedBranch?.locationLat != null &&
        selectedBranch?.locationLng != null) {
      return 'https://www.google.com/maps/dir/?api=1&destination='
          '${selectedBranch!.locationLat},${selectedBranch.locationLng}';
    }
    final address = selectedBranch?.address?.trim();
    if (address != null && address.isNotEmpty) {
      return 'https://www.google.com/maps/dir/?api=1&destination='
          '${Uri.encodeComponent(address)}';
    }
    return null;
  }

  Future<void> _openDirections(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await openExternalUrl(url);
    if (opened || !mounted) return;

    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    messenger?.showSnackBar(
      const SnackBar(content: Text('Konum linki kopyalandı.')),
    );
  }

  Future<void> _editWorkOrder() async {
    await showCreateWorkOrderDialog(context, ref, initialOrder: widget.order);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('İş emri güncellendi.')));
  }

  Widget _buildStatusActions(BuildContext context) {
    return AppSectionCard(
      title: 'Durum Değiştir',
      subtitle: 'Açık iş emrini yönet ve kapat',
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.order.status == 'open') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      'Detayları güncelle veya operasyonu başlat.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Gap(10),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _editWorkOrder,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Düzenle'),
                  ),
                ],
              ),
            ),
            const Gap(12),
          ],
          Row(
            children: [
              if (widget.order.status == 'open')
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _updateStatus('in_progress'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Başla'),
                  ),
                ),
              if (widget.order.status == 'in_progress') ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _updateStatus('open'),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Açığa Al'),
                  ),
                ),
              ],
              const Gap(12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                  ),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _isClosing = true),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Kapat'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsCard(BuildContext context) {
    final isDone = widget.order.status == 'done';
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '',
      decimalDigits: 2,
    );

    return AppSectionCard(
      title: 'Ödemeler',
      subtitle: isDone
          ? 'Kaydedilmiş tahsilat bilgileri'
          : 'Kapanış sırasında işlenecek ödeme satırları',
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              if (!isDone)
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _payments.add(_PaymentDraft())),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Ödeme Ekle'),
                ),
            ],
          ),
          if (_loadingRates) ...[
            const Gap(10),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const Gap(8),
                Text(
                  'Kurlar yükleniyor...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ] else if (_exchangeRates.isNotEmpty) ...[
            const Gap(8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.currency_exchange_rounded,
                    size: 16,
                    color: AppTheme.success,
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      'USD: ${money.format(_exchangeRates['USD'] ?? 0)} TL | EUR: ${money.format(_exchangeRates['EUR'] ?? 0)} TL | GBP: ${money.format(_exchangeRates['GBP'] ?? 0)} TL',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF166534),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Gap(10),
          if (_payments.isEmpty && !isDone)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: const Color(0xFF64748B),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      'Ödeme eklemek için butona tıklayın.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (isDone && widget.order.payments.isNotEmpty) ...[
            const Gap(4),
            for (int i = 0; i < widget.order.payments.length; i++) ...[
              _SavedPaymentRow(payment: widget.order.payments[i], money: money),
              if (i != widget.order.payments.length - 1) const Gap(10),
            ],
          ],
          for (int i = 0; i < _payments.length; i++) ...[
            _PaymentRow(
              draft: _payments[i],
              canRemove: !isDone,
              onRemove: isDone || _saving
                  ? null
                  : () => setState(() {
                      _payments[i].dispose();
                      _payments.removeAt(i);
                    }),
              money: money,
              exchangeRates: _exchangeRates,
            ),
            if (i != _payments.length - 1) const Gap(10),
          ],
        ],
      ),
    );
  }

  Widget _buildSignatureCard(BuildContext context, CustomerDetail customer) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Müşteri İmzası', style: Theme.of(context).textTheme.titleSmall),
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
                controller: _signatureController,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const Gap(10),
          Row(
            children: [
              OutlinedButton(
                onPressed: _saving ? null : () => _signatureController.clear(),
                child: const Text('Temizle'),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  customer.email?.trim().isNotEmpty ?? false
                      ? 'İmza ile birlikte e-posta gönderilecek.'
                      : 'E-posta adresi yoksa gönderim yapılmaz.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBranchLocationCard(
    BuildContext context,
    AsyncValue<List<CustomerBranch>> branchesAsync,
  ) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Şube & Konum', style: Theme.of(context).textTheme.titleSmall),
          const Gap(10),
          branchesAsync.when(
            data: (branches) => DropdownButtonFormField<String?>(
              initialValue: _selectedBranchId ?? widget.order.branchId,
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
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _selectedBranchId = v),
              decoration: const InputDecoration(labelText: 'Şube'),
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          const Gap(12),
          TextField(
            controller: _addressController,
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
                  controller: _latController,
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
                  controller: _lngController,
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
    );
  }

  Widget _buildAdditionalSalesCard(BuildContext context) {
    return AppCard(
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
            value: _addLine,
            onChanged: _saving ? null : (v) => setState(() => _addLine = v),
            title: const Text('Hat Satışı Ekle'),
            subtitle: const Text('Başlangıç: bugün - Bitiş: yıl sonu'),
          ),
          if (_addLine) ...[
            const Gap(10),
            TextField(
              controller: _lineNumberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Hat Numarası',
                hintText: '90555...',
              ),
            ),
            const Gap(10),
            TextField(
              controller: _lineSimController,
              decoration: const InputDecoration(
                labelText: 'SIM Numarası',
                hintText: '89...',
              ),
            ),
          ],
          const Divider(height: 24),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _addGmp3,
            onChanged: _saving ? null : (v) => setState(() => _addGmp3 = v),
            title: const Text('GMP3 Lisansı Sat'),
            subtitle: const Text('Başlangıç: bugün - Bitiş: yıl sonu'),
          ),
          if (_addGmp3) ...[
            const Gap(10),
            TextField(
              controller: _gmp3NameController,
              decoration: const InputDecoration(
                labelText: 'Lisans Adı',
                hintText: 'GMP3 Lisansı',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context) {
    return AppCard(
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
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Açıklama',
              hintText: 'İş emri kapanışına dair açıklama girin',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, CustomerDetail customer) {
    if (_isClosing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _isClosing = false),
              child: const Text('Vazgeç'),
            ),
          ),
          const Gap(12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
              onPressed: _saving ? null : () => _closeWorkOrder(customer),
              child: _saving
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
      );
    }

    return OutlinedButton(
      onPressed: _saving ? null : () => Navigator.of(context).pop(),
      child: const Text('Kapat'),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const Gap(10),
        Text(
          '$label:',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
        ),
        const Gap(8),
        Expanded(
          child: Text(
            value,
            style:
                valueStyle ??
                Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _HeaderMetaChip extends StatelessWidget {
  const _HeaderMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const Gap(6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentDraft {
  _PaymentDraft();

  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  String currency = 'TRY';
  String method = 'cash';

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
    required this.exchangeRates,
  });

  final _PaymentDraft draft;
  final bool canRemove;
  final VoidCallback? onRemove;
  final NumberFormat money;
  final Map<String, double> exchangeRates;

  @override
  State<_PaymentRow> createState() => _PaymentRowState();
}

class _PaymentRowState extends State<_PaymentRow> {
  @override
  Widget build(BuildContext context) {
    final amount = widget.draft.amount;
    final currency = widget.draft.currency;
    final rate = widget.exchangeRates[currency];
    final tryAmount = amount != null && rate != null && currency != 'TRY'
        ? amount * rate
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
              flex: 3,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
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
                  const Gap(8),
                  DropdownButtonFormField<String>(
                    initialValue: widget.draft.method,
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                      DropdownMenuItem(
                        value: 'bank',
                        child: Text('Havale/EFT'),
                      ),
                      DropdownMenuItem(value: 'pos', child: Text('POS')),
                      DropdownMenuItem(
                        value: 'credit_card',
                        child: Text('Kredi Kartı'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => widget.draft.method = v ?? 'cash'),
                    decoration: const InputDecoration(labelText: 'Ödeme Türü'),
                  ),
                ],
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
        ),
        if (tryAmount != null) ...[
          const Gap(6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 14,
                  color: const Color(0xFF64748B),
                ),
                const Gap(6),
                Text(
                  '${widget.money.format(tryAmount)} TL',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SavedPaymentRow extends StatelessWidget {
  const _SavedPaymentRow({required this.payment, required this.money});

  final WorkOrderPayment payment;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final paidAt = payment.paidAt == null
        ? null
        : DateFormat('d MMM y HH:mm', 'tr_TR').format(payment.paidAt!);
    final methodLabel = _paymentMethodLabel(payment.paymentMethod);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.payments_rounded,
              size: 18,
              color: AppTheme.success,
            ),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${money.format(payment.amount)} ${payment.currency}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (payment.description?.trim().isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      payment.description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Gap(10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (methodLabel != null)
                Text(
                  methodLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (paidAt != null)
                Text(
                  paidAt,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _paymentMethodLabel(String? method) {
  return switch (method) {
    'cash' => 'Nakit',
    'bank' => 'Havale/EFT',
    'pos' => 'POS',
    'credit_card' => 'Kredi Kartı',
    'check' => 'Çek',
    'other' => 'Diğer',
    _ => null,
  };
}
