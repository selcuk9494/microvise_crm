import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

/// Başvuru formu için satış e-faturası oluşturur / bağlar.
///
/// - Uygun mevcut satış faturası yoksa E-Fatura listesinde **taslak** oluşturur
/// - Cihaz sicili varsa kalem `notes` (açıklama) alanına yazar
/// - Formda `invoice_number` doluysa ikinci fatura açmaz
///
/// Mevcut faturalama kuyruğu (`enqueueInvoiceItem`) ayrı kalır.
/// Hata durumunda exception fırlatır (UI popup gösterebilir).
Future<Map<String, dynamic>?> linkApplicationFormDeviceToInvoice(
  ApiClient apiClient, {
  required String applicationFormId,
  bool throwOnFailure = true,
}) async {
  final id = applicationFormId.trim();
  if (id.isEmpty) return null;
  try {
    final result = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'linkApplicationFormDeviceToInvoice',
        'applicationFormId': id,
      },
    );
    final reason = (result['reason'] ?? '').toString();
    final linked = result['linked'] == true || result['created'] == true;
    if (!linked && throwOnFailure) {
      throw Exception(_invoiceLinkFailureMessage(reason, result));
    }
    return result;
  } catch (e) {
    if (!throwOnFailure) return null;
    rethrow;
  }
}

String _invoiceLinkFailureMessage(String reason, Map<String, dynamic> result) {
  switch (reason) {
    case 'missing_customer':
      return 'E-Fatura oluşturulamadı: başvuru formunda müşteri seçili değil.';
    case 'error':
      final detail = (result['error'] ?? '').toString().trim();
      return detail.isEmpty
          ? 'E-Fatura oluşturulamadı.'
          : 'E-Fatura oluşturulamadı: $detail';
    default:
      final detail = (result['error'] ?? reason).toString().trim();
      return detail.isEmpty
          ? 'E-Fatura oluşturulamadı.'
          : 'E-Fatura oluşturulamadı: $detail';
  }
}

/// Upsert yanıtındaki `invoiceLink` alanını kontrol eder; başarısızsa exception.
void assertApplicationFormInvoiceLink(Map<String, dynamic>? response) {
  if (response == null) return;
  final link = response['invoiceLink'];
  if (link is! Map) return;
  final map = link.cast<String, dynamic>();
  final linked = map['linked'] == true || map['created'] == true;
  if (linked) return;
  final reason = (map['reason'] ?? '').toString();
  // Müşteri yoksa form kaydı yine de geçerli olabilir; çağıran UI karar verir.
  if (reason == 'missing_customer') {
    throw Exception(_invoiceLinkFailureMessage(reason, map));
  }
  if (reason == 'error' || (map['error'] != null)) {
    throw Exception(_invoiceLinkFailureMessage(reason, map));
  }
}

Future<void> showApplicationFormInvoiceError(
  BuildContext context,
  Object error,
) async {
  if (!context.mounted) return;
  final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('E-Fatura oluşturulamadı'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );
}

/// Satış faturası kaydından sonra boş kalemlere başvuru sicili doldurur.
Future<Map<String, dynamic>?> fillInvoiceDeviceNotesFromApplicationForms(
  ApiClient apiClient, {
  required String invoiceId,
}) async {
  final id = invoiceId.trim();
  if (id.isEmpty) return null;
  try {
    return await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'fillInvoiceDeviceNotesFromApplicationForms',
        'invoiceId': id,
      },
    );
  } catch (_) {
    return null;
  }
}
