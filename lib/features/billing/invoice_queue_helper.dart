import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> enqueueInvoiceItem(
  SupabaseClient client, {
  required String itemType,
  required String sourceTable,
  required String sourceId,
  required String description,
  String? customerId,
  double? amount,
  String currency = 'TRY',
  String? sourceEvent,
  String? sourceLabel,
}) async {
  final payload = <String, dynamic>{
    'customer_id': customerId,
    'item_type': itemType,
    'source_table': sourceTable,
    'source_id': sourceId,
    'description': description,
    'amount': amount,
    'currency': currency,
    'status': 'pending',
    'created_by': client.auth.currentUser?.id,
    'is_active': true,
    'source_event': sourceEvent,
    'source_label': sourceLabel,
  };

  try {
    await client.from('invoice_items').insert(payload);
  } catch (error) {
    final message = error.toString();
    final fallback = Map<String, dynamic>.from(payload);
    if (message.contains("'is_active' column")) {
      fallback.remove('is_active');
    }
    if (message.contains("'source_event' column")) {
      fallback.remove('source_event');
    }
    if (message.contains("'source_label' column")) {
      fallback.remove('source_label');
    }
    await client.from('invoice_items').insert(fallback);
  }
}

Map<String, dynamic>? invoiceLinkFromResponse(Map<String, dynamic>? response) {
  final link = response?['invoiceLink'];
  if (link is Map) return link.cast<String, dynamic>();
  return null;
}

bool invoiceLinkSucceeded(Map<String, dynamic>? link) {
  if (link == null) return false;
  return link['linked'] == true || link['created'] == true;
}

void showFormInvoiceLinkSnackBar(
  BuildContext context, {
  required Map<String, dynamic>? invoiceLink,
  required String formLabel,
}) {
  if (!context.mounted || invoiceLink == null) return;
  final messenger = ScaffoldMessenger.of(context);
  if (invoiceLinkSucceeded(invoiceLink)) {
    final number = (invoiceLink['invoiceNumber'] ?? '').toString().trim();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          number.isEmpty
              ? '$formLabel için e-fatura oluşturuldu.'
              : '$formLabel için e-fatura oluşturuldu: $number',
        ),
      ),
    );
    return;
  }
  final reason = (invoiceLink['reason'] ?? '').toString();
  if (reason == 'missing_customer') {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$formLabel kaydedildi; e-fatura için müşteri seçili değil.',
        ),
      ),
    );
    return;
  }
  if (reason == 'error' || invoiceLink['error'] != null) {
    final detail = (invoiceLink['error'] ?? reason).toString().trim();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          detail.isEmpty
              ? '$formLabel kaydedildi; e-fatura oluşturulamadı.'
              : '$formLabel kaydedildi; e-fatura hatası: $detail',
        ),
      ),
    );
  }
}
