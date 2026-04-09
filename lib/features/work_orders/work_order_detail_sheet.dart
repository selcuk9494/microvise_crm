import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/platform/current_position.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/customer_model.dart';
import '../customers/customers_providers.dart';
import '../dashboard/dashboard_providers.dart';
import '../stock/line_stock.dart';
import 'work_order_model.dart';
import 'currency_service.dart';
import 'work_order_share.dart';
import 'work_orders_providers.dart';

class _CloseNoteOption {
  const _CloseNoteOption({required this.id, required this.name});

  final String id;
  final String name;

  factory _CloseNoteOption.fromJson(Map<String, dynamic> json) {
    return _CloseNoteOption(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}

final workOrderCloseNotesDefinitionProvider =
    FutureProvider<List<_CloseNoteOption>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_work_order_close_notes'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map(_CloseNoteOption.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('work_order_close_notes')
      .select('id,name,is_active,sort_order')
      .eq('is_active', true)
      .order('sort_order');
  return (rows as List)
      .map((e) => _CloseNoteOption.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

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
  final _locationLinkController = TextEditingController();
  String? _customerFallbackLocationLink;

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: const Color(0xFF0F172A),
  );

  final SignatureController _personnelSignatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: const Color(0xFF0F172A),
  );

  bool _saving = false;
  bool _fetchingLocation = false;
  bool _addLine = false;
  bool _isClosing = false;
  String? _selectedCloseNoteId;

  final _lineNumberController = TextEditingController();
  final _lineSimController = TextEditingController();
  String? _lineOperator;
  String? _selectedLineStockId;

  String? _selectedBranchId;
  final List<_PaymentDraft> _payments = [];

  Map<String, double> _exchangeRates = {};
  bool _loadingRates = false;

  @override
  void initState() {
    super.initState();
    _loadExchangeRates();
    _locationLinkController.text = widget.order.locationLink ?? '';
  }

  Future<void> _loadExchangeRates() async {
    setState(() => _loadingRates = true);
    try {
      _exchangeRates = await CurrencyService.getExchangeRates();
    } catch (_) {
      _exchangeRates = {
        'USD': 34.50,
        'EUR': 37.20,
        'GBP': 43.80,
      };
    }
    if (mounted) setState(() => _loadingRates = false);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _locationLinkController.dispose();
    _signatureController.dispose();
    _personnelSignatureController.dispose();
    _lineNumberController.dispose();
    _lineSimController.dispose();
    for (final p in _payments) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      final result = await fetchCurrentPosition();
      if (result == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Konum alınamadı. İzinleri ve konum servislerini kontrol edin.',
            ),
          ),
        );
        return;
      }
      final lat = result.latitude.toStringAsFixed(6);
      final lng = result.longitude.toStringAsFixed(6);
      _locationLinkController.text = 'https://maps.google.com/?q=$lat,$lng';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum alındı.')),
      );
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  String? _resolvedLocationLink() {
    final raw = _locationLinkController.text.trim();
    if (raw.isNotEmpty) return raw;
    final rawFromOrder = (widget.order.locationLink ?? '').trim();
    if (rawFromOrder.isNotEmpty) return rawFromOrder;
    final fallback = (_customerFallbackLocationLink ?? '').trim();
    if (fallback.isNotEmpty) return fallback;
    return null;
  }

  ({double lat, double lng})? _extractLatLng(String link) {
    final qIndex = link.indexOf('?q=');
    if (qIndex != -1) {
      final q = link.substring(qIndex + 3);
      final parts = q.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) return (lat: lat, lng: lng);
      }
    }
    final parts = link.split(',');
    if (parts.length >= 2) {
      final lat = double.tryParse(parts[0].replaceAll(RegExp(r'[^0-9.+-]'), ''));
      final lng = double.tryParse(parts[1].replaceAll(RegExp(r'[^0-9.+-]'), ''));
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }
    return null;
  }

  Future<void> _openDirections() async {
    final link = _resolvedLocationLink();
    if (link == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum linki yok.')),
      );
      return;
    }
    final ok = await _openDirectionsLink(link);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harita açılamadı.')),
      );
    }
  }

  Future<bool> _openDirectionsLink(String link) async {
    final coords = _extractLatLng(link);
    final url = coords == null
        ? Uri.parse(link)
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${coords.lat},${coords.lng}',
          );
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _editWorkOrderLocation(
    CustomerDetail customer,
    List<CustomerLocation> locations,
  ) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final addressController = TextEditingController(
      text: (widget.order.address ?? '').trim(),
    );
    final linkController = TextEditingController(
      text: (widget.order.locationLink ?? '').trim(),
    );
    final latController = TextEditingController();
    final lngController = TextEditingController();

    String? selectedCustomerLocationId;
    var saveToCustomer = true;
    var fetching = false;

    String? resolvedLink() {
      final raw = linkController.text.trim();
      if (raw.isNotEmpty) return raw;
      final lat = latController.text.trim();
      final lng = lngController.text.trim();
      if (lat.isEmpty || lng.isEmpty) return null;
      return 'https://maps.google.com/?q=$lat,$lng';
    }

    CustomerLocation? findById(String id) {
      for (final l in locations) {
        if (l.id == id) return l;
      }
      return null;
    }

    void applyLocation(CustomerLocation? l) {
      if (l == null) return;
      titleController.text = l.title;
      descriptionController.text = l.description ?? '';
      addressController.text = l.address ?? '';
      linkController.text = l.locationLink ?? '';
      latController.text = l.locationLat?.toString() ?? '';
      lngController.text = l.locationLng?.toString() ?? '';
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (sheetContext, setLocal) {
                Future<void> fetch() async {
                  setLocal(() => fetching = true);
                  try {
                    final result = await fetchCurrentPosition();
                    if (result == null) return;
                    final lat = result.latitude.toStringAsFixed(6);
                    final lng = result.longitude.toStringAsFixed(6);
                    latController.text = lat;
                    lngController.text = lng;
                    linkController.text = 'https://maps.google.com/?q=$lat,$lng';
                  } finally {
                    setLocal(() => fetching = false);
                  }
                }

                Future<void> save() async {
                  final link = resolvedLink();
                  if (link == null || link.trim().isEmpty) {
                    if (sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('Konum linki boş olamaz.')),
                      );
                    }
                    return;
                  }

                  final title = titleController.text.trim();
                  final description = descriptionController.text.trim();
                  final address = addressController.text.trim();
                  final lat = double.tryParse(latController.text.trim());
                  final lng = double.tryParse(lngController.text.trim());

                  if (apiClient != null) {
                    await apiClient.patchJson(
                      '/work-orders',
                      body: {
                        'id': widget.order.id,
                        'location_link': link,
                        if (address.isNotEmpty) 'address': address,
                      },
                    );

                    if (saveToCustomer) {
                      final profile =
                          await ref.read(currentUserProfileProvider.future);
                      final payload = {
                        'customer_id': customer.id,
                        'title': title.isEmpty ? 'İş Emri Konumu' : title,
                        'description': description.isEmpty ? null : description,
                        'address': address.isEmpty ? null : address,
                        'location_link': link,
                        'location_lat': lat,
                        'location_lng': lng,
                        'is_active': true,
                      };
                      if (selectedCustomerLocationId != null) {
                        await apiClient.postJson(
                          '/mutate',
                          body: {
                            'op': 'updateWhere',
                            'table': 'customer_locations',
                            'filters': [
                              {
                                'col': 'id',
                                'op': 'eq',
                                'value': selectedCustomerLocationId,
                              },
                            ],
                            'values': payload,
                          },
                        );
                      } else {
                        await apiClient.postJson(
                          '/mutate',
                          body: {
                            'op': 'insertMany',
                            'table': 'customer_locations',
                            'rows': [
                              {
                                ...payload,
                                'created_by': profile?.id,
                              },
                            ],
                          },
                        );
                      }
                      ref.invalidate(customerLocationsProvider(customer.id));
                    }
                  } else {
                    await client!.from('work_orders').update({
                      'location_link': link,
                      if (address.isNotEmpty) 'address': address,
                    }).eq('id', widget.order.id);

                    if (saveToCustomer) {
                      final payload = {
                        'customer_id': customer.id,
                        'title': title.isEmpty ? 'İş Emri Konumu' : title,
                        'description': description.isEmpty ? null : description,
                        'address': address.isEmpty ? null : address,
                        'location_link': link,
                        'location_lat': lat,
                        'location_lng': lng,
                        'is_active': true,
                      };
                      if (selectedCustomerLocationId != null) {
                        await client
                            .from('customer_locations')
                            .update(payload)
                            .eq('id', selectedCustomerLocationId!);
                      } else {
                        await client.from('customer_locations').insert({
                          ...payload,
                          'created_by': client.auth.currentUser?.id,
                        });
                      }
                      ref.invalidate(customerLocationsProvider(customer.id));
                    }
                  }

                  ref.invalidate(workOrdersBoardProvider);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Konum kaydedildi.')),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Konum',
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Gap(12),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedCustomerLocationId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Yeni konum'),
                        ),
                        ...locations.map(
                          (l) => DropdownMenuItem<String?>(
                            value: l.id,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.title),
                                if ((l.description ?? '').trim().isNotEmpty)
                                  Text(
                                    l.description!.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: const Color(0xFF64748B)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (id) {
                        setLocal(() {
                          selectedCustomerLocationId = id;
                          if (id == null) return;
                          applyLocation(findById(id));
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Müşteri Konumu',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Konum Başlığı',
                        hintText: 'Örn. Şube / Mağaza / Depo',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Konum Açıklaması',
                        hintText: 'Kapı, kat, mağaza içi notlar...',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Adres',
                        hintText: 'Cadde, sokak, no, ilçe...',
                      ),
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: linkController,
                            decoration: const InputDecoration(
                              labelText: 'Konum Linki',
                              hintText: 'Google Maps linki',
                            ),
                          ),
                        ),
                        const Gap(12),
                        OutlinedButton.icon(
                          onPressed: fetching ? null : fetch,
                          icon: fetching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location_rounded),
                          label: const Text('Konum Al'),
                        ),
                      ],
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
                              labelText: 'Lat',
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
                              labelText: 'Lng',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: saveToCustomer,
                      onChanged: (v) => setLocal(() => saveToCustomer = v),
                      title: const Text('Müşteriye konum olarak kaydet'),
                      subtitle: const Text('Bu konum müşteri kayıtlarına işlensin.'),
                    ),
                    const Gap(12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: save,
                        child: const Text('Kaydet'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    } finally {
      titleController.dispose();
      descriptionController.dispose();
      addressController.dispose();
      linkController.dispose();
      latController.dispose();
      lngController.dispose();
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.patchJson(
          '/work-orders',
          body: {'id': widget.order.id, 'status': newStatus},
        );
      } else {
        await client!.from('work_orders').update({
          'status': newStatus,
        }).eq('id', widget.order.id);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İş emri durumu güncellendi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Durum güncellenemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeWorkOrder(CustomerDetail customer) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      final isAdmin = ref.read(isAdminProvider);
      if (_addLine && !isAdmin && ((_selectedLineStockId ?? '').trim().isEmpty)) {
        throw Exception('Personel stoktan hat seçmelidir.');
      }
      final now = DateTime.now().toUtc();
      final profile = await ref.read(currentUserProfileProvider.future);
      final signatureBytes = await _signatureController.toPngBytes();
      final signaturePng =
          signatureBytes == null || signatureBytes.isEmpty ? null : signatureBytes;
      final personnelSignatureBytes = await _personnelSignatureController.toPngBytes();
      final personnelSignaturePng = personnelSignatureBytes == null ||
              personnelSignatureBytes.isEmpty
          ? null
          : personnelSignatureBytes;
      String? closeNotesText =
          _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
      if (_addLine) {
        final number = _lineNumberController.text.trim();
        final sim = _lineSimController.text.trim();
        final op = (_lineOperator ?? '').trim();
        String opLabel(String v) {
          final k = v.toLowerCase();
          if (k == 'turkcell') return 'TURKCELL';
          if (k == 'telsim') return 'TELSİM';
          return v.trim().isEmpty ? '-' : v.toUpperCase();
        }

        final extra = [
          'Ek Satış: Hat',
          if (op.isNotEmpty) opLabel(op),
          if (number.isNotEmpty) number,
          if (sim.isNotEmpty) 'SIM: $sim',
        ].join(' • ');
        closeNotesText = [
          if ((closeNotesText ?? '').trim().isNotEmpty) closeNotesText!.trim(),
          extra,
        ].join('\n');
      }
      final closedPayments = _payments
          .map((p) {
            final amount = p.amount;
            if (amount == null) return null;
            final desc = p.descriptionController.text.trim();
            return WorkOrderPayment(
              amount: amount,
              currency: p.currency,
              paidAt: now,
              description: desc.isEmpty ? null : desc,
              paymentMethod: p.method,
              isActive: true,
            );
          })
          .whereType<WorkOrderPayment>()
          .toList(growable: false);

      final branchId = _selectedBranchId ?? widget.order.branchId;
      String? insertedLineId;

      if (_addLine) {
        final number = _lineNumberController.text.trim();
        if (number.isEmpty) {
          throw Exception('Hat numarası gerekli.');
        }
        final op = (_lineOperator ?? '').trim();
        if (op.isEmpty) throw Exception('Operatör seçin.');

        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, 12, 31);
        final linePayload = {
          'customer_id': customer.id,
          'branch_id': branchId,
          'number': number,
          'operator': op,
          'sim_number':
              _lineSimController.text.trim().isEmpty ? null : _lineSimController.text.trim(),
          'starts_at': start.toIso8601String().substring(0, 10),
          'ends_at': end.toIso8601String().substring(0, 10),
          'expires_at': end.toIso8601String().substring(0, 10),
          'is_active': true,
        };
        if (apiClient != null) {
          final response = await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'lines',
              'returning': 'row',
              'values': linePayload,
            },
          );
          insertedLineId = (response['row'] as Map?)?['id']?.toString();
        } else {
          final row = await client!
              .from('lines')
              .insert(linePayload)
              .select('id')
              .single();
          insertedLineId = row['id']?.toString();
        }
      }

      if ((insertedLineId ?? '').trim().isNotEmpty &&
          (_selectedLineStockId ?? '').trim().isNotEmpty &&
          apiClient != null) {
        try {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'line_stock',
              'filters': [
                {'col': 'id', 'op': 'eq', 'value': _selectedLineStockId},
              ],
              'values': {
                'consumed_at': now.toIso8601String(),
                'consumed_by': profile?.id,
                'consumed_customer_id': customer.id,
                'consumed_work_order_id': widget.order.id,
                'consumed_line_id': insertedLineId,
              },
            },
          );
          ref.invalidate(lineStockAvailableProvider);
        } catch (_) {}
      }

      if (apiClient != null) {
        final invoiceRows = <Map<String, dynamic>>[];
        if ((insertedLineId ?? '').trim().isNotEmpty) {
          final number = _lineNumberController.text.trim();
          invoiceRows.add({
            'customer_id': customer.id,
            'item_type': 'line_activation',
            'source_table': 'lines',
            'source_id': insertedLineId,
            'description': 'Hat Aktivasyonu - ${customer.name} / $number',
            'currency': 'TRY',
            'status': 'pending',
            'is_active': true,
            'created_by': profile?.id,
            'source_event': 'line_activated',
            'source_label': 'Hat Aktivasyonu',
          });
        }
        if (invoiceRows.isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {'op': 'insertMany', 'table': 'invoice_items', 'rows': invoiceRows},
          );
        }
      } else {
        if (client != null) {
          if ((insertedLineId ?? '').trim().isNotEmpty) {
            final number = _lineNumberController.text.trim();
            try {
              await client.from('invoice_items').insert({
                'customer_id': customer.id,
                'item_type': 'line_activation',
                'source_table': 'lines',
                'source_id': insertedLineId,
                'description': 'Hat Aktivasyonu - ${customer.name} / $number',
                'currency': 'TRY',
                'status': 'pending',
                'is_active': true,
                'created_by': client.auth.currentUser?.id,
                'source_event': 'line_activated',
                'source_label': 'Hat Aktivasyonu',
              });
            } catch (_) {
              await client.from('invoice_items').insert({
                'customer_id': customer.id,
                'item_type': 'line_activation',
                'source_table': 'lines',
                'source_id': insertedLineId,
                'description': 'Hat Aktivasyonu - ${customer.name} / $number',
                'currency': 'TRY',
                'status': 'pending',
                'is_active': true,
                'created_by': client.auth.currentUser?.id,
              });
            }
          }
        }
      }

      final paymentRows = <Map<String, dynamic>>[];
      for (final p in _payments) {
        final amount = p.amount;
        if (amount == null) continue;
        final description = p.descriptionController.text.trim();
        paymentRows.add({
          'customer_id': customer.id,
          'work_order_id': widget.order.id,
          'amount': amount,
          'currency': p.currency,
          'exchange_rate': p.currency == 'TRY' ? 1.0 : _exchangeRates[p.currency],
          'payment_method': p.method,
          'description': description.isEmpty ? null : description,
          'paid_at': now.toIso8601String(),
          'is_active': true,
        });
      }
      if (paymentRows.isNotEmpty) {
        if (apiClient != null) {
          await apiClient.postJson(
            '/mutate',
            body: {'op': 'insertMany', 'table': 'payments', 'rows': paymentRows},
          );
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'insertMany',
              'table': 'invoice_items',
              'rows': paymentRows
                  .map(
                    (row) => {
                      'customer_id': customer.id,
                      'item_type': 'work_order_payment',
                      'source_table': 'work_orders',
                      'source_id': widget.order.id,
                      'description': [
                        'İş Emri Ödemesi',
                        widget.order.title.trim().isEmpty
                            ? null
                            : widget.order.title.trim(),
                        row['description']?.toString().trim().isEmpty ?? true
                            ? null
                            : row['description']?.toString().trim(),
                      ].whereType<String>().join(' - '),
                      'amount': row['amount'],
                      'currency': row['currency'],
                      'status': 'pending',
                      'is_active': true,
                      'created_by': profile?.id,
                      'source_event': 'work_order_payment',
                      'source_label': 'İş Emri Ödemesi',
                    },
                  )
                  .toList(growable: false),
            },
          );
        } else {
          await client!.from('payments').insert(paymentRows);
          await client.from('invoice_items').insert(
                paymentRows
                    .map(
                      (row) => {
                        'customer_id': customer.id,
                        'item_type': 'work_order_payment',
                        'source_table': 'work_orders',
                        'source_id': widget.order.id,
                        'description': [
                          'İş Emri Ödemesi',
                          widget.order.title.trim().isEmpty
                              ? null
                              : widget.order.title.trim(),
                          row['description']?.toString().trim().isEmpty ?? true
                              ? null
                              : row['description']?.toString().trim(),
                        ].whereType<String>().join(' - '),
                        'amount': row['amount'],
                        'currency': row['currency'],
                        'status': 'pending',
                        'is_active': true,
                        'created_by': client.auth.currentUser?.id,
                      },
                    )
                    .toList(growable: false),
              );
        }
      }

      final workOrderUpdate = {
        'status': 'done',
        'branch_id': branchId,
        'closed_at': now.toIso8601String(),
        'closed_by': profile?.id,
        'location_link': _resolvedLocationLink(),
        'close_notes': closeNotesText,
      };
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'work_orders',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.order.id},
            ],
            'values': workOrderUpdate,
          },
        );
      } else {
        await client!.from('work_orders').update(workOrderUpdate).eq('id', widget.order.id);
      }

      final customerSigDataUrl = signaturePng == null
          ? null
          : 'data:image/png;base64,${base64Encode(signaturePng)}';
      final personnelSigDataUrl = personnelSignaturePng == null
          ? null
          : 'data:image/png;base64,${base64Encode(personnelSignaturePng)}';
      if (customerSigDataUrl != null || personnelSigDataUrl != null) {
        try {
          if (apiClient != null) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'upsert',
                'table': 'work_order_signatures',
                'values': {
                  'id': widget.order.id,
                  'work_order_id': widget.order.id,
                  'customer_signature_data_url': customerSigDataUrl,
                  'personnel_signature_data_url': personnelSigDataUrl,
                },
              },
            );
          } else {
            await client!.from('work_order_signatures').upsert({
              'id': widget.order.id,
              'work_order_id': widget.order.id,
              'customer_signature_data_url': customerSigDataUrl,
              'personnel_signature_data_url': personnelSigDataUrl,
            });
          }
        } catch (_) {}
      }

      if (!mounted) return;
      ref.invalidate(dashboardMetricsProvider);
      final shareNow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('İş emri kapatıldı'),
          content: Text(
            kIsWeb ? 'PDF olarak kaydetmek ister misin?' : 'PDF olarak paylaşmak ister misin?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Sonra'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(kIsWeb ? 'Kaydet' : 'Paylaş'),
            ),
          ],
        ),
      );
      if (shareNow == true) {
        final pdfOrder = WorkOrder.fromJson({
          ...widget.order.toJson(),
          'status': 'done',
          'closed_at': now.toIso8601String(),
          'close_notes': closeNotesText,
          'payments': closedPayments.map((e) => e.toJson()).toList(growable: false),
        });
        if (!mounted) return;
        await shareWorkOrderPdf(
          order: pdfOrder,
          customer: customer,
          closeNotes: closeNotesText,
          payments: closedPayments,
          signaturePngBytes: signaturePng,
          personnelSignaturePngBytes: personnelSignaturePng,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shareNow == true ? 'PDF paylaşıma hazırlandı.' : 'İş emri kapatıldı.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync =
        ref.watch(customerDetailProvider(widget.order.customerId));
    final branchesAsync =
        ref.watch(customerBranchesProvider(widget.order.customerId));
    final customerLocationsAsync =
        ref.watch(customerLocationsProvider(widget.order.customerId));
    final isDone = widget.order.status == 'done';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
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
                const Gap(14),
                _buildHeader(context, customer),
                const Gap(14),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _buildInfoCard(
                        context,
                        customer,
                        customerLocationsAsync: customerLocationsAsync,
                      ),
                      const Gap(12),
                      if (!isDone && !_isClosing) ...[
                        _buildStatusActions(context),
                        const Gap(12),
                      ],
                      if (_isClosing || isDone) ...[
                        _buildPaymentsCard(context),
                        const Gap(12),
                        if (isDone) ...[
                          _buildLocationCard(context),
                          const Gap(12),
                        ],
                        if (!isDone) ...[
                          _buildSignatureCard(context, customer),
                          const Gap(12),
                          _buildBranchLocationCard(context, branchesAsync),
                          const Gap(12),
                          _buildLocationCard(context),
                          const Gap(12),
                          _buildAdditionalSalesCard(context),
                          const Gap(12),
                          _buildNotesCard(context),
                          const Gap(12),
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
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(18),
              child: AppCard(
                child: Text(
                  'Müşteri bilgisi yüklenemedi.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
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
    final isDone = widget.order.status == 'done';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.order.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Gap(4),
              Text(
                customer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        AppBadge(label: statusLabel, tone: statusTone),
        if (isDone) ...[
          const Gap(10),
          IconButton.filledTonal(
            tooltip: 'PDF Paylaş',
            onPressed: _saving
                ? null
                : () async {
                    final apiClient = ref.read(apiClientProvider);
                    final client = ref.read(supabaseClientProvider);
                    WorkOrder pdfOrder = widget.order;
                    Uint8List? customerSigBytes;
                    Uint8List? personnelSigBytes;
                    try {
                      if (apiClient != null) {
                        final response = await apiClient.getJson(
                          '/data',
                          queryParameters: {
                            'resource': 'work_order_detail',
                            'workOrderId': widget.order.id,
                          },
                        );
                        final item =
                            (response['item'] as Map?)?.cast<String, dynamic>();
                        if (item != null) {
                          pdfOrder = WorkOrder.fromJson(item);
                          customerSigBytes =
                              _decodePngDataUrl(pdfOrder.customerSignatureDataUrl);
                          personnelSigBytes = _decodePngDataUrl(
                            pdfOrder.personnelSignatureDataUrl,
                          );
                        }
                      } else if (client != null) {
                        final rows = await client
                            .from('payments')
                            .select('amount,currency,paid_at,description,payment_method,is_active')
                            .eq('work_order_id', widget.order.id)
                            .eq('is_active', true)
                            .order('paid_at', ascending: true)
                            .limit(2000);
                        final payments = (rows as List)
                            .map((e) => WorkOrderPayment.fromJson(e as Map<String, dynamic>))
                            .toList(growable: false);
                        final sigRows = await client
                            .from('work_order_signatures')
                            .select(
                              'customer_signature_data_url,personnel_signature_data_url',
                            )
                            .eq('work_order_id', widget.order.id)
                            .limit(1);
                        final sig = (sigRows as List).isEmpty
                            ? null
                            : (sigRows.first as Map).cast<String, dynamic>();
                        customerSigBytes =
                            _decodePngDataUrl(sig?['customer_signature_data_url']?.toString());
                        personnelSigBytes =
                            _decodePngDataUrl(sig?['personnel_signature_data_url']?.toString());
                        pdfOrder = WorkOrder.fromJson({
                          ...widget.order.toJson(),
                          'payments': payments.map((e) => e.toJson()).toList(growable: false),
                        });
                      }
                    } catch (_) {}

                    if (!context.mounted) return;
                    await shareWorkOrderPdf(
                      order: pdfOrder,
                      customer: customer,
                      closeNotes: (pdfOrder.closeNotes ?? '').trim().isEmpty
                          ? null
                          : pdfOrder.closeNotes,
                      payments: pdfOrder.payments,
                      signaturePngBytes: customerSigBytes,
                      personnelSignaturePngBytes: personnelSigBytes,
                    );
                  },
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ],
    );
  }

  Uint8List? _decodePngDataUrl(String? dataUrl) {
    final raw = (dataUrl ?? '').trim();
    if (raw.isEmpty) return null;
    final prefix = 'data:image/png;base64,';
    final base64Part = raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
    try {
      final bytes = base64Decode(base64Part);
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  List<({String title, String? description, String? address, String link})>
      _customerLocationLinks(List<CustomerLocation> locations) {
    final active = locations.where((e) => e.isActive).toList(growable: false);
    final result = <({String title, String? description, String? address, String link})>[];
    for (final l in active) {
      final direct = (l.locationLink ?? '').trim();
      final lat = l.locationLat;
      final lng = l.locationLng;
      final link = direct.isNotEmpty
          ? direct
          : (lat == null || lng == null)
              ? ''
              : 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
      if (link.isEmpty) continue;
      result.add((
        title: l.title.trim().isEmpty ? 'Konum' : l.title.trim(),
        description: l.description?.trim().isEmpty ?? true ? null : l.description!.trim(),
        address: l.address?.trim().isEmpty ?? true ? null : l.address!.trim(),
        link: link,
      ));
    }
    return result;
  }

  Widget _buildInfoCard(
    BuildContext context,
    CustomerDetail customer, {
    required AsyncValue<List<CustomerLocation>> customerLocationsAsync,
  }) {
    final dateText = widget.order.scheduledDate != null
        ? DateFormat('d MMMM y', 'tr_TR').format(widget.order.scheduledDate!)
        : 'Tarih belirlenmedi';

    final address = (widget.order.address ?? '').trim();
    final city = (widget.order.city ?? '').trim();
    final addressText = [
      if (address.isNotEmpty) address,
      if (city.isNotEmpty) city,
    ].join(' • ');
    final branchName = (widget.order.branchName ?? '').trim();
    final assigned = (widget.order.assignedPersonnelName ?? '').trim();
    final description = (widget.order.description ?? '').trim();
    final closeNotes = (widget.order.closeNotes ?? '').trim();
    final rawOrderLink = (widget.order.locationLink ?? '').trim();

    final rawLocations = customerLocationsAsync.asData?.value ?? const [];
    final locationItems = _customerLocationLinks(rawLocations);
    if (rawOrderLink.isEmpty && locationItems.isNotEmpty) {
      _customerFallbackLocationLink = locationItems.first.link;
    }
    final customerLocationTitle = locationItems.isEmpty ? null : locationItems.first.title;
    final link = _resolvedLocationLink();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('İş Emri Detayları',
              style: Theme.of(context).textTheme.titleSmall),
          const Gap(12),
          _InfoRow(icon: Icons.business_rounded, label: 'Müşteri', value: customer.name),
          const Gap(8),
          _InfoRow(icon: Icons.calendar_today_rounded, label: 'Planlanan Tarih', value: dateText),
          if (branchName.isNotEmpty) ...[
            const Gap(8),
            _InfoRow(icon: Icons.store_mall_directory_rounded, label: 'Şube', value: branchName),
          ],
          if (assigned.isNotEmpty) ...[
            const Gap(8),
            _InfoRow(icon: Icons.badge_rounded, label: 'Atanan', value: assigned),
          ],
          if (addressText.isNotEmpty) ...[
            const Gap(8),
            _InfoRow(icon: Icons.home_work_rounded, label: 'Adres', value: addressText),
          ],
          if (description.isNotEmpty) ...[
            const Gap(8),
            _InfoRow(icon: Icons.notes_rounded, label: 'Açıklama', value: description),
          ],
          if (link != null) ...[
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: _InfoRow(
                    icon: Icons.location_on_rounded,
                    label: 'Konum',
                    value: rawOrderLink.isNotEmpty
                        ? 'İş Emri Konumu'
                        : (customerLocationTitle == null
                            ? 'Müşteri Konumu'
                            : 'Müşteri: $customerLocationTitle'),
                  ),
                ),
                const Gap(10),
                OutlinedButton.icon(
                  onPressed: _openDirections,
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: const Text('Tarif Al'),
                ),
                const Gap(6),
                IconButton(
                  tooltip: 'Konumu Düzenle',
                  onPressed: () => _editWorkOrderLocation(customer, rawLocations),
                  icon: const Icon(Icons.edit_location_alt_rounded),
                ),
              ],
            ),
            if (locationItems.length >= 2) ...[
              const Gap(10),
              Text(
                'Tüm Konumlar',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF64748B)),
              ),
              const Gap(6),
              Column(
                children: [
                  for (final item in locationItems)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.place_rounded,
                            size: 18,
                            color: Color(0xFF64748B),
                          ),
                          const Gap(10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if ((item.description ?? '').trim().isNotEmpty) ...[
                                  const Gap(2),
                                  Text(
                                    item.description!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: const Color(0xFF64748B)),
                                  ),
                                ],
                                if ((item.address ?? '').trim().isNotEmpty) ...[
                                  const Gap(2),
                                  Text(
                                    item.address!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Gap(10),
                          IconButton(
                            tooltip: 'Tarif',
                            onPressed: () async {
                              final ok = await _openDirectionsLink(item.link);
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Harita açılamadı.')),
                                );
                              }
                            },
                            icon: const Icon(Icons.directions_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
          if (customer.email?.isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(icon: Icons.email_rounded, label: 'E-posta', value: customer.email!),
          ],
          if (customer.phone1?.isNotEmpty ?? false) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.phone_rounded,
              label: 'Telefon',
              value: customer.phone1!,
              phoneActions: true,
            ),
          ],
          const Gap(8),
          Row(
            children: [
              Icon(
                widget.order.paymentRequired == null
                    ? Icons.help_outline_rounded
                    : widget.order.paymentRequired!
                        ? Icons.payments_rounded
                        : Icons.money_off_csred_rounded,
                size: 18,
                color: widget.order.paymentRequired == null
                    ? Colors.grey
                    : widget.order.paymentRequired!
                        ? Colors.red
                        : Colors.red,
              ),
              const Gap(10),
              Expanded(
                child: Text(
                  widget.order.paymentRequired == null
                      ? 'ÖDEME BELİRSİZ'
                      : widget.order.paymentRequired!
                          ? 'ÖDEME ALINACAK'
                          : 'ÖDEME ALINMAYACAK',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: widget.order.paymentRequired == null
                            ? Colors.grey
                            : Colors.red,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          if ((widget.order.contactPhone ?? '').trim().isNotEmpty) ...[
            const Gap(8),
            _InfoRow(
              icon: Icons.phone_in_talk_rounded,
              iconColor: Colors.red,
              label: 'İrtibat',
              labelColor: Colors.red,
              value: widget.order.contactPhone!.trim(),
              valueColor: Colors.red,
              phoneActions: true,
            ),
          ],
          if (closeNotes.isNotEmpty) ...[
            const Gap(8),
            _InfoRow(icon: Icons.fact_check_rounded, label: 'Kapanış', value: closeNotes),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard(BuildContext context) {
    final isDone = widget.order.status == 'done';
    final link = _resolvedLocationLink();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Konum', style: Theme.of(context).textTheme.titleSmall),
              ),
              if (!isDone)
                OutlinedButton.icon(
                  onPressed: _fetchingLocation ? null : _fetchLocation,
                  icon: _fetchingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Konum Al'),
                ),
              const Gap(10),
              OutlinedButton.icon(
                onPressed: link == null ? null : _openDirections,
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('Tarif Al'),
              ),
            ],
          ),
          const Gap(10),
          TextField(
            controller: _locationLinkController,
            readOnly: isDone,
            decoration: const InputDecoration(
              labelText: 'Konum Linki',
              hintText: 'Konum al ile otomatik dolar',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusActions(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Durum Değiştir', style: Theme.of(context).textTheme.titleSmall),
          const Gap(12),
          Row(
            children: [
              if (widget.order.status == 'open')
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _updateStatus('in_progress'),
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
                        : () {
                            ref.invalidate(workOrderCloseNotesDefinitionProvider);
                            setState(() => _isClosing = true);
                          },
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
    final money =
        NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    Text('Ödemeler', style: Theme.of(context).textTheme.titleSmall),
              ),
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
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
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
                  Icon(Icons.currency_exchange_rounded,
                      size: 16, color: AppTheme.success),
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
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: const Color(0xFF64748B)),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      'Ödeme eklemek için butona tıklayın.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),
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
          Text('İmzalar', style: Theme.of(context).textTheme.titleSmall),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: _SignatureBox(
                  title: 'Müşteri İmzası',
                  controller: _signatureController,
                  onClear: _saving ? null : _signatureController.clear,
                ),
              ),
              const Gap(10),
              Expanded(
                child: _SignatureBox(
                  title: 'Personel İmzası',
                  controller: _personnelSignatureController,
                  onClear: _saving ? null : _personnelSignatureController.clear,
                ),
              ),
            ],
          ),
          const Gap(10),
          Text(
            customer.email?.trim().isNotEmpty ?? false
                ? 'İmza ile birlikte e-posta gönderilecek.'
                : 'E-posta adresi yoksa gönderim yapılmaz.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchLocationCard(
      BuildContext context, AsyncValue<List<CustomerBranch>> branchesAsync) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              onChanged:
                  _saving ? null : (v) => setState(() => _selectedBranchId = v),
              decoration: const InputDecoration(labelText: 'Şube'),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalSalesCard(BuildContext context) {
    final lineStockAsync = ref.watch(lineStockAvailableProvider);
    final operatorValue = (_lineOperator ?? '').trim().isEmpty ? null : _lineOperator!.trim();
    final isAdmin = ref.watch(isAdminProvider);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ek Satış (opsiyonel)',
              style: Theme.of(context).textTheme.titleSmall),
          const Gap(10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _addLine,
            onChanged: _saving
                ? null
                : (v) => setState(() {
                      _addLine = v;
                      if (v && (_lineOperator ?? '').trim().isEmpty) {
                        _lineOperator = 'turkcell';
                      }
                      if (!v) {
                        _lineOperator = null;
                        _selectedLineStockId = null;
                      }
                    }),
            title: const Text('Hat Satışı Ekle'),
            subtitle: const Text('Başlangıç: bugün - Bitiş: yıl sonu'),
          ),
          if (_addLine) ...[
            const Gap(10),
            lineStockAsync.when(
              data: (items) {
                final available = items
                    .where((e) => e.isActive && !e.isConsumed)
                    .toList(growable: false);
                final selectedId = (_selectedLineStockId ?? '').trim();
                LineStockItem? selected;
                if (selectedId.isNotEmpty) {
                  for (final s in available) {
                    if (s.id == selectedId) {
                      selected = s;
                      break;
                    }
                  }
                }

                Future<void> openPicker() async {
                  var q = '';
                  final picked = await showModalBottomSheet<LineStockItem?>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setSheetState) {
                        List<LineStockItem> filtered() {
                          final needle = q.trim().toLowerCase();
                          if (needle.isEmpty) return available;
                          return available.where((e) {
                            final hay = [
                              e.lineNumber,
                              e.simNumber ?? '',
                              e.operatorName,
                            ].join(' ').toLowerCase();
                            return hay.contains(needle);
                          }).toList(growable: false);
                        }

                        final list = filtered();
                        return SafeArea(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                              top: 8,
                            ),
                            child: SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.72,
                              child: Column(
                                children: [
                                  TextField(
                                    onChanged: (v) => setSheetState(() => q = v),
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search_rounded),
                                      hintText: 'Ara (hat, sim, operatör...)',
                                    ),
                                  ),
                                  const Gap(10),
                                  Expanded(
                                    child: ListView(
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.clear_rounded),
                                          title: const Text('Seçimi temizle'),
                                          onTap: () => Navigator.of(context).pop(null),
                                        ),
                                        const Divider(height: 1),
                                        for (final s in list)
                                          ListTile(
                                            title: Text(s.lineNumber),
                                            subtitle: Text(
                                              [
                                                normalizeOperator(s.operatorName) == 'turkcell'
                                                    ? 'TURKCELL'
                                                    : normalizeOperator(s.operatorName) ==
                                                            'telsim'
                                                        ? 'TELSİM'
                                                        : s.operatorName,
                                                if ((s.simNumber ?? '').trim().isNotEmpty)
                                                  'SIM: ${s.simNumber}',
                                              ].where((e) => e.trim().isNotEmpty).join(' • '),
                                            ),
                                            onTap: () => Navigator.of(context).pop(s),
                                          ),
                                        if (list.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Text('Kayıt yok.'),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                  setState(() {
                    if (picked == null) {
                      _selectedLineStockId = null;
                      return;
                    }
                    _selectedLineStockId = picked.id;
                    _lineNumberController.text = picked.lineNumber;
                    _lineSimController.text = (picked.simNumber ?? '').trim();
                    _lineOperator = normalizeOperator(picked.operatorName);
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving || available.isEmpty ? null : openPicker,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: Text(
                        selected == null
                            ? (available.isEmpty ? 'Stok yok' : 'Stoktan seç (arama)')
                            : [
                                selected.lineNumber,
                                if ((selected.simNumber ?? '').trim().isNotEmpty)
                                  'SIM: ${selected.simNumber}',
                              ].join(' • '),
                      ),
                    ),
                    const Gap(6),
                    Text(
                      'Stok: ${available.length} kayıt',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 56,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Text(
                'Hat stok yüklenemedi.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted),
              ),
            ),
            if (isAdmin) ...[
              const Gap(10),
              TextField(
                controller: _lineNumberController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Hat Numarası',
                  hintText: '90555...',
                ),
                onChanged: _saving
                    ? null
                    : (_) => setState(() => _selectedLineStockId = null),
              ),
              const Gap(10),
              DropdownButtonFormField<String>(
                initialValue: operatorValue,
                items: const [
                  DropdownMenuItem(value: 'turkcell', child: Text('TURKCELL')),
                  DropdownMenuItem(value: 'telsim', child: Text('TELSİM')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _lineOperator = v),
                decoration: const InputDecoration(labelText: 'Operatör (Zorunlu)'),
              ),
              const Gap(10),
              TextField(
                controller: _lineSimController,
                decoration: const InputDecoration(
                  labelText: 'SIM Numarası',
                  hintText: '89...',
                ),
                onChanged: _saving
                    ? null
                    : (_) => setState(() => _selectedLineStockId = null),
              ),
            ] else ...[
              const Gap(8),
              Text(
                'Personel sadece stoktan hat seçebilir.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context) {
    final closeNotesAsync = ref.watch(workOrderCloseNotesDefinitionProvider);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kapatma Şekli', style: Theme.of(context).textTheme.titleSmall),
          const Gap(10),
          closeNotesAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return Text(
                  'Tanımlamalar > Kapanış Açıklaması bölümünden kapatma şekli ekleyin.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textMuted),
                );
              }
              return DropdownButtonFormField<String?>(
                initialValue: _selectedCloseNoteId,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Kapatma şekli seç'),
                  ),
                  ...items.map(
                    (e) => DropdownMenuItem<String?>(
                      value: e.id,
                      child: Text(e.name),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() => _selectedCloseNoteId = value);
                        final selected = items
                            .where((e) => e.id == value)
                            .firstOrNull;
                        if (selected == null) return;
                        if (_notesController.text.trim().isEmpty) {
                          _notesController.text = selected.name;
                        }
                      },
                decoration: const InputDecoration(labelText: 'Seçim'),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(
              'Kapatma şekli listesi yüklenemedi: $error',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textMuted),
            ),
          ),
          const Gap(12),
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Detay',
              hintText: 'İsteğe bağlı ek detay yazın',
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
              onPressed:
                  _saving ? null : () => setState(() => _isClosing = false),
              child: const Text('Vazgeç'),
            ),
          ),
          const Gap(12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
              ),
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

class _SignatureBox extends StatelessWidget {
  const _SignatureBox({
    required this.title,
    required this.controller,
    required this.onClear,
  });

  final String title;
  final SignatureController controller;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            TextButton(
              onPressed: onClear,
              child: const Text('Temizle'),
            ),
          ],
        ),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Signature(
              controller: controller,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.labelColor,
    this.valueColor,
    this.phoneActions = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final Color? labelColor;
  final Color? valueColor;
  final bool phoneActions;

  @override
  Widget build(BuildContext context) {
    final v = value.trim();
    final canAct = phoneActions && v.isNotEmpty && v != '—';

    String normalizeDigits(String input) {
      final digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
      if (digits.startsWith('+')) return digits.substring(1);
      if (digits.startsWith('00')) return digits.substring(2);
      return digits;
    }

    String normalizeForWhatsApp(String input) {
      final d = normalizeDigits(input);
      if (d.startsWith('90') && d.length >= 11) return d;
      if (d.startsWith('0') && d.length == 11) return '90${d.substring(1)}';
      if (d.length == 10) return '90$d';
      return d;
    }

    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: v));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kopyalandı.')),
      );
    }

    Future<void> openActions() async {
      final tel = normalizeDigits(v);
      final wa = normalizeForWhatsApp(v);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const Gap(4),
                Text(
                  v,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
                const Gap(12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call_rounded),
                  title: const Text('Ara'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final uri = Uri(scheme: 'tel', path: tel.isEmpty ? v : tel);
                    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Arama açılamadı.')),
                      );
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_rounded),
                  title: const Text('WhatsApp'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (wa.trim().isEmpty && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Numara geçersiz.')),
                      );
                      return;
                    }
                    final url = Uri.parse('https://wa.me/$wa');
                    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('WhatsApp açılamadı.')),
                      );
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Kopyala'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await copy();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor ?? const Color(0xFF64748B)),
        const Gap(10),
        Text(
          '$label:',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: labelColor ?? const Color(0xFF64748B)),
        ),
        const Gap(8),
        Expanded(
          child: canAct
              ? InkWell(
                  onTap: openActions,
                  onLongPress: copy,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: valueColor,
                          ),
                    ),
                  ),
                )
              : Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: valueColor,
                      ),
                ),
        ),
        if (canAct) ...[
          const Gap(6),
          IconButton(
            tooltip: 'Kopyala',
            onPressed: copy,
            icon: Icon(Icons.copy_rounded, size: 18, color: valueColor),
          ),
        ],
      ],
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
              child: TextField(
                controller: widget.draft.amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tutar',
                  hintText: '0.00',
                ),
                onChanged: (_) => setState(() {}),
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
        ),
        const Gap(10),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: widget.draft.method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                  DropdownMenuItem(value: 'transfer', child: Text('Havale')),
                  DropdownMenuItem(value: 'cheque', child: Text('Çek')),
                  DropdownMenuItem(value: 'pos', child: Text('POS')),
                ],
                onChanged: (v) =>
                    setState(() => widget.draft.method = v ?? 'cash'),
                decoration: const InputDecoration(labelText: 'Ödeme Tipi'),
              ),
            ),
            const Gap(10),
            Expanded(
              flex: 5,
              child: TextField(
                controller: widget.draft.descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Örn: Kurulum tahsilatı',
                ),
              ),
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
                Icon(Icons.swap_horiz_rounded,
                    size: 14, color: const Color(0xFF64748B)),
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
