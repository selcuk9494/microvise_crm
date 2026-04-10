import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../billing/invoice_queue_helper.dart';
import '../../core/platform/current_position.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/customer_model.dart';
import '../customers/customers_providers.dart';
import '../stock/line_stock.dart';
import 'work_order_model.dart';
import 'work_order_share.dart';

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
  final _locationTitleController = TextEditingController();
  final _locationDescriptionController = TextEditingController();
  final _locationLinkController = TextEditingController();

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: const Color(0xFF0F172A),
  );

  final SignatureController _personnelSignatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: const Color(0xFF0F172A),
  );

  bool _saving = false;
  bool _addLine = false;
  bool _saveAsCustomerLocation = false;
  bool _fetchingLocation = false;

  final _lineNumberController = TextEditingController();
  final _lineSimController = TextEditingController();
  String? _lineOperator;
  String? _selectedLineStockId;

  String? _selectedBranchId;
  String? _selectedCustomerLocationId;
  final List<_PaymentDraft> _payments = [_PaymentDraft()];

  @override
  void dispose() {
    _notesController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _addressController.dispose();
    _locationTitleController.dispose();
    _locationDescriptionController.dispose();
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

  Future<void> _save(CustomerDetail customer) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now().toUtc();
      final locationLink = _resolvedLocationLink();
      final profile = await ref.read(currentUserProfileProvider.future);
      final isAdmin = ref.read(isAdminProvider);
      if (_addLine && !isAdmin && ((_selectedLineStockId ?? '').trim().isEmpty)) {
        throw Exception('Personel stoktan hat seçmelidir.');
      }

      final branchId = _selectedBranchId ?? widget.order.branchId;
      if (apiClient != null) {
        String? insertedLineId;
        String normalizeDigits(String input) =>
            input.replaceAll(RegExp(r'[^0-9]'), '');
        if (_addLine) {
          final number = _lineNumberController.text.trim();
          if (number.isEmpty) {
            throw Exception('Hat numarası gerekli.');
          }
          final op = (_lineOperator ?? '').trim();
          if (op.isEmpty) throw Exception('Operatör seçin.');
          final start = DateTime(now.year, now.month, now.day);
          final end = DateTime(now.year, 12, 31);
          final response = await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'lines',
              'returning': 'row',
              'values': {
                'customer_id': customer.id,
                'branch_id': branchId,
                'number': number,
                'operator': op,
                'sim_number': _lineSimController.text.trim().isEmpty
                    ? null
                    : _lineSimController.text.trim(),
                'starts_at': start.toIso8601String().substring(0, 10),
                'ends_at': end.toIso8601String().substring(0, 10),
                'expires_at': end.toIso8601String().substring(0, 10),
                'is_active': true,
              },
            },
          );
          insertedLineId = (response['row'] as Map?)?['id']?.toString();
        }

        var stockId = (_selectedLineStockId ?? '').trim();
        if (isAdmin && (insertedLineId ?? '').trim().isNotEmpty && stockId.isEmpty) {
          final entered = normalizeDigits(_lineNumberController.text.trim());
          if (entered.isNotEmpty) {
            final available = await ref.read(lineStockAvailableProvider.future);
            final matched = available.where((e) {
              final n = normalizeDigits(e.lineNumber);
              return n.isNotEmpty && n == entered;
            }).toList(growable: false);
            if (matched.isNotEmpty) {
              stockId = matched.first.id;
            }
          }
        }

        if ((insertedLineId ?? '').trim().isNotEmpty && stockId.isNotEmpty) {
          try {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'line_stock',
                'filters': [
                  {'col': 'id', 'op': 'eq', 'value': stockId},
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

        final paymentRows = <Map<String, dynamic>>[];
        for (final p in _payments) {
          final amount = p.amount;
          if (amount == null) continue;
          paymentRows.add({
            'customer_id': customer.id,
            'work_order_id': widget.order.id,
            'amount': amount,
            'currency': p.currency,
            'exchange_rate': p.currency == 'TRY' ? 1.0 : null,
            'payment_method': p.method,
            'description': p.description,
            'paid_at': now.toIso8601String(),
            'is_active': true,
          });
        }
        if (paymentRows.isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {'op': 'insertMany', 'table': 'payments', 'rows': paymentRows},
          );
          invoiceRows.addAll(
            paymentRows.map(
              (row) => {
                'customer_id': customer.id,
                'item_type': 'work_order_payment',
                'source_table': 'work_orders',
                'source_id': widget.order.id,
                'description': [
                  'İş Emri Ödemesi',
                  widget.order.title.trim().isEmpty ? null : widget.order.title.trim(),
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
            ),
          );
        }
        if (invoiceRows.isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {'op': 'insertMany', 'table': 'invoice_items', 'rows': invoiceRows},
          );
        }

        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'work_orders',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.order.id},
            ],
            'values': {
              'status': 'done',
              'branch_id': branchId,
              'location_link': locationLink,
              'closed_at': now.toIso8601String(),
              'closed_by': profile?.id,
              'close_notes': _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
            },
          },
        );

        if (branchId != null) {
          final lat = double.tryParse(_latController.text.trim());
          final lng = double.tryParse(_lngController.text.trim());
          final address = _addressController.text.trim();
          final latMap = lat == null ? null : {'location_lat': lat};
          final lngMap = lng == null ? null : {'location_lng': lng};
          final addressMap = address.isEmpty ? null : {'address': address};
          final values = {...?latMap, ...?lngMap, ...?addressMap};
          if (values.isNotEmpty) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'branches',
                'filters': [
                  {'col': 'id', 'op': 'eq', 'value': branchId},
                ],
                'values': values,
              },
            );
          }
        }

        if (_saveAsCustomerLocation) {
          final title = _locationTitleController.text.trim();
          final description = _locationDescriptionController.text.trim();
          final address = _addressController.text.trim();
          final lat = double.tryParse(_latController.text.trim());
          final lng = double.tryParse(_lngController.text.trim());

          if (title.isNotEmpty ||
              description.isNotEmpty ||
              address.isNotEmpty ||
              locationLink != null ||
              lat != null ||
              lng != null) {
            final payload = {
              'customer_id': customer.id,
              'title': title.isEmpty ? 'İş Emri Konumu' : title,
              'description': description.isEmpty ? null : description,
              'address': address.isEmpty ? null : address,
              'location_link': locationLink,
              'location_lat': lat,
              'location_lng': lng,
              'is_active': true,
            };

            if (_selectedCustomerLocationId != null) {
              await apiClient.postJson(
                '/mutate',
                body: {
                  'op': 'updateWhere',
                  'table': 'customer_locations',
                  'filters': [
                    {'col': 'id', 'op': 'eq', 'value': _selectedCustomerLocationId},
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
        }

        if (!mounted) return;
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
              return WorkOrderPayment(
                amount: amount,
                currency: p.currency,
                paidAt: now,
                description: p.description,
                paymentMethod: p.method,
                isActive: true,
              );
            })
            .whereType<WorkOrderPayment>()
            .toList(growable: false);

        try {
          final signatureBytes = await _signatureController.toPngBytes();
          final signaturePng = signatureBytes == null || signatureBytes.isEmpty
              ? null
              : signatureBytes;
          final personnelSignatureBytes =
              await _personnelSignatureController.toPngBytes();
          final personnelSignaturePng = personnelSignatureBytes == null ||
                  personnelSignatureBytes.isEmpty
              ? null
              : personnelSignatureBytes;
          final customerSigDataUrl = signaturePng == null
              ? null
              : 'data:image/png;base64,${base64Encode(signaturePng)}';
          final personnelSigDataUrl = personnelSignaturePng == null
              ? null
              : 'data:image/png;base64,${base64Encode(personnelSignaturePng)}';
          if (customerSigDataUrl != null || personnelSigDataUrl != null) {
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
          }
        } catch (_) {}

        if (!mounted) return;
          final shareNow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('İş emri kapatıldı'),
              content: Text(
                kIsWeb
                    ? 'PDF olarak kaydetmek ister misin?'
                    : 'PDF olarak paylaşmak ister misin?',
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
          final signatureBytes = await _signatureController.toPngBytes();
          final signaturePng = signatureBytes == null || signatureBytes.isEmpty
              ? null
              : signatureBytes;
          final personnelSignatureBytes =
              await _personnelSignatureController.toPngBytes();
          final personnelSignaturePng = personnelSignatureBytes == null ||
                  personnelSignatureBytes.isEmpty
              ? null
              : personnelSignatureBytes;
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
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shareNow == true ? 'PDF paylaşıma hazırlandı.' : 'İş emri kapatıldı.',
            ),
          ),
        );
        return;
      }

      if (client == null) return;
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

      if (_saveAsCustomerLocation) {
        final title = _locationTitleController.text.trim();
        final description = _locationDescriptionController.text.trim();
        final address = _addressController.text.trim();
        final lat = double.tryParse(_latController.text.trim());
        final lng = double.tryParse(_lngController.text.trim());

        if (title.isNotEmpty ||
            description.isNotEmpty ||
            address.isNotEmpty ||
            locationLink != null ||
            lat != null ||
            lng != null) {
          final payload = {
            'customer_id': customer.id,
            'title': title.isEmpty ? 'İş Emri Konumu' : title,
            'description': description.isEmpty ? null : description,
            'address': address.isEmpty ? null : address,
            'location_link': locationLink,
            'location_lat': lat,
            'location_lng': lng,
            'is_active': true,
          };

          if (_selectedCustomerLocationId != null) {
            await client
                .from('customer_locations')
                .update(payload)
                .eq('id', _selectedCustomerLocationId!);
          } else {
            await client.from('customer_locations').insert({
              ...payload,
              'created_by': client.auth.currentUser?.id,
            });
          }
          ref.invalidate(customerLocationsProvider(customer.id));
        }
      }

      if (_addLine) {
        final isAdmin = ref.read(isAdminProvider);
        if (!isAdmin && ((_selectedLineStockId ?? '').trim().isEmpty)) {
          throw Exception('Personel stoktan hat seçmelidir.');
        }
        String normalizeDigits(String input) =>
            input.replaceAll(RegExp(r'[^0-9]'), '');
        final number = _lineNumberController.text.trim();
        if (number.isEmpty) {
          throw Exception('Hat numarası gerekli.');
        }
        final op = (_lineOperator ?? '').trim();
        if (op.isEmpty) throw Exception('Operatör seçin.');

        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, 12, 31);
        final insertedLine = await client
            .from('lines')
            .insert({
          'customer_id': customer.id,
          'branch_id': branchId,
          'number': number,
          'operator': op,
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
        final insertedLineId = insertedLine['id']?.toString();
        var stockId = (_selectedLineStockId ?? '').trim();
        if (isAdmin && (insertedLineId ?? '').trim().isNotEmpty && stockId.isEmpty) {
          final entered = normalizeDigits(_lineNumberController.text.trim());
          if (entered.isNotEmpty) {
            final available = await ref.read(lineStockAvailableProvider.future);
            final matched = available.where((e) {
              final n = normalizeDigits(e.lineNumber);
              return n.isNotEmpty && n == entered;
            }).toList(growable: false);
            if (matched.isNotEmpty) {
              stockId = matched.first.id;
            }
          }
        }

        if ((insertedLineId ?? '').trim().isNotEmpty && stockId.isNotEmpty) {
          try {
            await client
                .from('line_stock')
                .update({
                  'consumed_at': now.toIso8601String(),
                  'consumed_by': client.auth.currentUser?.id,
                  'consumed_customer_id': customer.id,
                  'consumed_work_order_id': widget.order.id,
                  'consumed_line_id': insertedLineId,
                })
                .eq('id', stockId);
          } catch (_) {}
        }
        await enqueueInvoiceItem(
          client,
          itemType: 'line_activation',
          sourceTable: 'lines',
          sourceId: insertedLineId.toString(),
          customerId: customer.id,
          description: 'Hat Aktivasyonu - ${customer.name} / $number',
          sourceEvent: 'line_activated',
          sourceLabel: 'Hat Aktivasyonu',
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
      Uint8List? personnelSignatureBytes =
          await _personnelSignatureController.toPngBytes();
      String? personnelSignatureDataUrl;
      if (personnelSignatureBytes != null && personnelSignatureBytes.isNotEmpty) {
        personnelSignatureDataUrl =
            'data:image/png;base64,${base64Encode(personnelSignatureBytes)}';
      }

      await client
          .from('work_orders')
          .update({
            'status': 'done',
            'branch_id': branchId,
            'location_link': locationLink,
            'closed_at': now.toIso8601String(),
            'closed_by': client.auth.currentUser?.id,
            'close_notes': _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          })
          .eq('id', widget.order.id);

      if (signatureDataUrl != null || personnelSignatureDataUrl != null) {
        try {
          await client.from('work_order_signatures').upsert({
            'id': widget.order.id,
            'work_order_id': widget.order.id,
            'customer_signature_data_url': signatureDataUrl,
            'personnel_signature_data_url': personnelSignatureDataUrl,
          });
        } catch (_) {}
      }

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
      final closeNotesText = _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim();
      final closedPayments = _payments
          .map((p) {
            final amount = p.amount;
            if (amount == null) return null;
            return WorkOrderPayment(
              amount: amount,
              currency: p.currency,
              paidAt: now,
              description: p.description,
              paymentMethod: p.method,
              isActive: true,
            );
          })
          .whereType<WorkOrderPayment>()
          .toList(growable: false);

      final shareNow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('İş emri kapatıldı'),
          content: Text(
            kIsWeb
                ? 'PDF olarak kaydetmek ister misin?'
                : 'PDF olarak paylaşmak ister misin?',
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
          signaturePngBytes: signatureBytes,
          personnelSignaturePngBytes: personnelSignatureBytes,
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              'Konum alınamadı. İzin veya tarayıcı desteğini kontrol edin.',
            ),
          ),
        );
        return;
      }

      final lat = result.latitude.toStringAsFixed(6);
      final lng = result.longitude.toStringAsFixed(6);
      _latController.text = lat;
      _lngController.text = lng;
      _locationLinkController.text = 'https://maps.google.com/?q=$lat,$lng';

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Konum alındı.')));
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  String? _resolvedLocationLink() {
    final rawLink = _locationLinkController.text.trim();
    if (rawLink.isNotEmpty) {
      return rawLink;
    }
    final lat = _latController.text.trim();
    final lng = _lngController.text.trim();
    if (lat.isEmpty || lng.isEmpty) {
      return null;
    }
    return 'https://maps.google.com/?q=$lat,$lng';
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(
      customerDetailProvider(widget.order.customerId),
    );
    final branchesAsync = ref.watch(
      customerBranchesProvider(widget.order.customerId),
    );
    final customerLocationsAsync = ref.watch(
      customerLocationsProvider(widget.order.customerId),
    );
    final lineStockAsync = ref.watch(lineStockAvailableProvider);

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
              customerLocationsAsync: customerLocationsAsync,
              lineStockAsync: lineStockAsync,
              selectedLineStockId: _selectedLineStockId,
              onLineStockSelected: _saving
                  ? null
                  : (item) => setState(() {
                        if (item == null) {
                          _selectedLineStockId = null;
                          return;
                        }
                        _selectedLineStockId = item.id;
                        _lineNumberController.text = item.lineNumber;
                        _lineSimController.text = (item.simNumber ?? '').trim();
                        _lineOperator = normalizeOperator(item.operatorName);
                      }),
              selectedBranchId: _selectedBranchId ?? widget.order.branchId,
              onBranchChanged: _saving
                  ? null
                  : (id) => setState(() => _selectedBranchId = id),
              selectedCustomerLocationId: _selectedCustomerLocationId,
              onCustomerLocationChanged: _saving
                  ? null
                  : (id, locations) {
                      setState(() {
                        _selectedCustomerLocationId = id;
                        if (id == null) return;
                        CustomerLocation? selected;
                        for (final location in locations) {
                          if (location.id == id) {
                            selected = location;
                            break;
                          }
                        }
                        if (selected == null) return;
                        _locationTitleController.text = selected.title;
                        _locationDescriptionController.text =
                            selected.description ?? '';
                        _addressController.text = selected.address ?? '';
                        _locationLinkController.text =
                            selected.locationLink ?? '';
                        _latController.text =
                            selected.locationLat?.toString() ?? '';
                        _lngController.text =
                            selected.locationLng?.toString() ?? '';
                      });
                    },
              notesController: _notesController,
              addressController: _addressController,
              latController: _latController,
              lngController: _lngController,
              locationLinkController: _locationLinkController,
              locationTitleController: _locationTitleController,
              locationDescriptionController: _locationDescriptionController,
              fetchingLocation: _fetchingLocation,
              onFetchLocation: _saving ? null : _fetchLocation,
              saveAsCustomerLocation: _saveAsCustomerLocation,
              onToggleSaveAsCustomerLocation: _saving
                  ? null
                  : (value) => setState(() => _saveAsCustomerLocation = value),
              isAdmin: ref.watch(isAdminProvider),
              addLine: _addLine,
              onToggleAddLine: _saving
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
              lineNumberController: _lineNumberController,
              lineSimController: _lineSimController,
              lineOperator: _lineOperator,
              onLineOperatorChanged: _saving
                  ? null
                  : (v) => setState(() => _lineOperator = v),
              signatureController: _signatureController,
              personnelSignatureController: _personnelSignatureController,
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
    required this.customerLocationsAsync,
    required this.lineStockAsync,
    required this.selectedLineStockId,
    required this.onLineStockSelected,
    required this.selectedBranchId,
    required this.onBranchChanged,
    required this.selectedCustomerLocationId,
    required this.onCustomerLocationChanged,
    required this.notesController,
    required this.addressController,
    required this.latController,
    required this.lngController,
    required this.locationLinkController,
    required this.locationTitleController,
    required this.locationDescriptionController,
    required this.fetchingLocation,
    required this.onFetchLocation,
    required this.saveAsCustomerLocation,
    required this.onToggleSaveAsCustomerLocation,
    required this.isAdmin,
    required this.addLine,
    required this.onToggleAddLine,
    required this.lineNumberController,
    required this.lineSimController,
    required this.lineOperator,
    required this.onLineOperatorChanged,
    required this.signatureController,
    required this.personnelSignatureController,
    required this.payments,
    required this.saving,
    required this.onAddPayment,
    required this.onRemovePayment,
    required this.onSave,
  });

  final WorkOrder order;
  final CustomerDetail customer;
  final AsyncValue<List<CustomerBranch>> branchesAsync;
  final AsyncValue<List<CustomerLocation>> customerLocationsAsync;
  final AsyncValue<List<LineStockItem>> lineStockAsync;
  final String? selectedLineStockId;
  final ValueChanged<LineStockItem?>? onLineStockSelected;
  final String? selectedBranchId;
  final ValueChanged<String?>? onBranchChanged;
  final String? selectedCustomerLocationId;
  final void Function(String?, List<CustomerLocation>)?
  onCustomerLocationChanged;
  final TextEditingController notesController;
  final TextEditingController addressController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final TextEditingController locationLinkController;
  final TextEditingController locationTitleController;
  final TextEditingController locationDescriptionController;
  final bool fetchingLocation;
  final VoidCallback? onFetchLocation;
  final bool saveAsCustomerLocation;
  final ValueChanged<bool>? onToggleSaveAsCustomerLocation;
  final bool isAdmin;
  final bool addLine;
  final ValueChanged<bool>? onToggleAddLine;
  final TextEditingController lineNumberController;
  final TextEditingController lineSimController;
  final String? lineOperator;
  final ValueChanged<String?>? onLineOperatorChanged;
  final SignatureController signatureController;
  final SignatureController personnelSignatureController;
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
    final lineOperatorValue =
        (lineOperator ?? '').trim().isEmpty ? null : lineOperator!.trim();
    final manualAllowed = isAdmin;

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
                    customerLocationsAsync.when(
                      data: (locations) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String?>(
                            initialValue: selectedCustomerLocationId,
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Kayıtlı konum seç (opsiyonel)'),
                              ),
                              ...locations.map(
                                (location) => DropdownMenuItem<String?>(
                                  value: location.id,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(location.title),
                                      if ((location.description ?? '').trim().isNotEmpty)
                                        Text(
                                          location.description!.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF64748B),
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            onChanged: onCustomerLocationChanged == null
                                ? null
                                : (value) =>
                                      onCustomerLocationChanged!(value, locations),
                            decoration: const InputDecoration(
                              labelText: 'Müşteri Konumu',
                            ),
                          ),
                          if (locations.isEmpty) ...[
                            const Gap(6),
                            Text(
                              'Kayıtlı konum yok. Konum Al ile konum getirip “Müşteriye konum olarak kaydet” seçeneğiyle ekleyebilirsin.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                          ],
                        ],
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (error, stackTrace) => const SizedBox.shrink(),
                    ),
                    const Gap(12),
                    TextField(
                      controller: locationTitleController,
                      decoration: const InputDecoration(
                        labelText: 'Konum Başlığı',
                        hintText: 'Örn. Servis Noktası',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: locationDescriptionController,
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
                        labelText: 'Adres (güncelle)',
                        hintText: 'Cadde, sokak, no, ilçe...',
                      ),
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: locationLinkController,
                            decoration: const InputDecoration(
                              labelText: 'Konum Linki',
                              hintText: 'Google Maps veya paylaşım linki',
                            ),
                          ),
                        ),
                        const Gap(12),
                        OutlinedButton.icon(
                          onPressed: fetchingLocation ? null : onFetchLocation,
                          icon: fetchingLocation
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                    const Gap(12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: saveAsCustomerLocation,
                      onChanged: onToggleSaveAsCustomerLocation,
                      title: const Text('Müşteriye konum olarak kaydet'),
                      subtitle: const Text(
                        'Bu konum kapanışta müşteri kayıtlarına işlensin.',
                      ),
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
                    Text('İmzalar', style: Theme.of(context).textTheme.titleSmall),
                    const Gap(10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Müşteri İmzası',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: saving ? null : signatureController.clear,
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
                                    controller: signatureController,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Gap(10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Personel İmzası',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: saving
                                        ? null
                                        : personnelSignatureController.clear,
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
                                    controller: personnelSignatureController,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(10),
                    Text(
                      customer.email?.trim().isNotEmpty ?? false
                          ? 'İmza ile birlikte e-posta gönderimi denenecek.'
                          : 'E-posta yoksa gönderim yapılmaz.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFF64748B)),
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
                      lineStockAsync.when(
                        data: (items) {
                          final available = items
                              .where((e) => e.isActive && !e.isConsumed)
                              .toList(growable: false);
                          final selectedId = (selectedLineStockId ?? '').trim();
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
                                              onChanged: (v) =>
                                                  setSheetState(() => q = v),
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
                                                    onTap: () =>
                                                        Navigator.of(context).pop(null),
                                                  ),
                                                  const Divider(height: 1),
                                                  for (final s in list)
                                                    ListTile(
                                                      title: Text(s.lineNumber),
                                                      subtitle: Text(
                                                        [
                                                          normalizeOperator(s.operatorName) ==
                                                                  'turkcell'
                                                              ? 'TURKCELL'
                                                              : normalizeOperator(
                                                                          s.operatorName) ==
                                                                      'telsim'
                                                                  ? 'TELSİM'
                                                                  : s.operatorName,
                                                          if ((s.simNumber ?? '')
                                                              .trim()
                                                              .isNotEmpty)
                                                            'SIM: ${s.simNumber}',
                                                        ].where((e) => e.trim().isNotEmpty).join(' • '),
                                                      ),
                                                      onTap: () =>
                                                          Navigator.of(context).pop(s),
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
                            onLineStockSelected?.call(picked);
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: saving || available.isEmpty ? null : openPicker,
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
                                    ?.copyWith(color: const Color(0xFF64748B)),
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
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ),
                      if (manualAllowed) ...[
                        const Gap(10),
                        TextField(
                          controller: lineNumberController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Hat Numarası',
                            hintText: '90555...',
                          ),
                          onChanged: saving ? null : (_) => onLineStockSelected?.call(null),
                        ),
                        const Gap(10),
                        DropdownButtonFormField<String>(
                          initialValue: lineOperatorValue,
                          items: const [
                            DropdownMenuItem(
                              value: 'turkcell',
                              child: Text('TURKCELL'),
                            ),
                            DropdownMenuItem(
                              value: 'telsim',
                              child: Text('TELSİM'),
                            ),
                          ],
                          onChanged: saving ? null : onLineOperatorChanged,
                          decoration: const InputDecoration(
                            labelText: 'Operatör (Zorunlu)',
                          ),
                        ),
                        const Gap(10),
                        TextField(
                          controller: lineSimController,
                          decoration: const InputDecoration(
                            labelText: 'SIM Numarası',
                            hintText: '89...',
                          ),
                          onChanged: saving ? null : (_) => onLineStockSelected?.call(null),
                        ),
                      ] else ...[
                        const Gap(8),
                        Text(
                          'Personel sadece stoktan hat seçebilir.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ],
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
                  DropdownMenuItem(value: 'bank', child: Text('Havale/EFT')),
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
    );
  }
}
