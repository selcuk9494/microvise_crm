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
