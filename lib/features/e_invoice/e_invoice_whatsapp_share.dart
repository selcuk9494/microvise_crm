import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../app/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/open_external_url.dart';
import '../customers/customer_detail_screen.dart';
import '../invoices/invoice_model.dart';
import 'e_invoice_pdf_share.dart';

String _phoneLabel(String? title, String fallback) {
  final trimmed = (title ?? '').trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

void _addCustomerPhones(
  void Function(String label, String? number) addPhone,
  CustomerDetail customer,
) {
  addPhone(_phoneLabel(customer.phone1Title, 'Müşteri'), customer.phone1);
  addPhone(_phoneLabel(customer.phone2Title, 'İrtibat'), customer.phone2);
  addPhone(_phoneLabel(customer.phone3Title, 'İrtibat 2'), customer.phone3);
}

/// E-fatura PDF'ini WhatsApp sohbetine yönlendirerek paylaşır.
///
/// Masaüstünde / Electron'da WhatsApp URL ile dosya eklenemez; PDF yerel olarak
/// açılır (veya Finder'da gösterilir) ve kullanıcı sohbete ekler.
Future<void> shareEInvoicePdfWithWhatsApp({
  required BuildContext context,
  required Invoice invoice,
  required String pdfUrl,
  String? pdfBase64,
  CustomerDetail? customer,
}) async {
  final options = <_PhoneOption>[];

  void addPhone(String label, String? number) {
    final raw = (number ?? '').trim();
    if (raw.isEmpty) return;
    final normalizedKey = _normalizePhoneKey(raw);
    if (normalizedKey.isEmpty) return;
    if (options.any((o) => _normalizePhoneKey(o.phone) == normalizedKey)) {
      return;
    }
    options.add(_PhoneOption(label: label, phone: raw));
  }

  if (customer != null) {
    _addCustomerPhones(addPhone, customer);
  }

  final action = await showModalBottomSheet<_ShareAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WhatsApp ile gönder',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Gap(6),
            Text(
              options.isEmpty
                  ? 'Cariye kayıtlı numara yok. Numara girin veya PDF’i açıp sohbete ekleyin.'
                  : 'Numara seçin; WhatsApp sohbeti açılır. PDF yerel olarak hazırlanır — sohbete ekleyin.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            ),
            const Gap(12),
            for (final opt in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.messageCircle),
                title: Text(opt.label),
                subtitle: Text(opt.phone),
                onTap: () =>
                    Navigator.of(context).pop(_ShareAction.whatsApp(opt.phone)),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.phoneCall),
              title: const Text('Başka numara'),
              onTap: () =>
                  Navigator.of(context).pop(const _ShareAction.other()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.fileType2),
              title: const Text('Sadece PDF aç'),
              onTap: () =>
                  Navigator.of(context).pop(const _ShareAction.openPdfOnly()),
            ),
          ],
        ),
      ),
    ),
  );

  if (action == null) return;
  if (!context.mounted) return;

  String? phoneToUse;
  if (action.kind == _ShareActionKind.other) {
    final input = await _askPhoneNumber(context);
    if (!context.mounted) return;
    if (input == null) return;
    phoneToUse = input;
  } else if (action.kind == _ShareActionKind.whatsapp) {
    phoneToUse = action.phone;
  }

  final message = buildEInvoiceWhatsAppMessage(
    invoice: invoice,
    customerName: customer?.name ?? invoice.customerName,
  );
  await Clipboard.setData(ClipboardData(text: message));

  if (phoneToUse != null) {
    final waPhone = normalizePhoneForWhatsApp(phoneToUse);
    final url = waPhone.isEmpty
        ? Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}')
        : Uri.parse(
            'https://wa.me/$waPhone?text=${Uri.encodeComponent(message)}',
          );
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened) {
      await openExternalUrl(url.toString());
    }
  }

  final number = (invoice.eInvoiceNumber?.trim().isNotEmpty ?? false)
      ? invoice.eInvoiceNumber!.trim().replaceFirst(RegExp(r'^\d{9}-'), '')
      : invoice.invoiceNumber.trim();
  final customerName = (invoice.customerName ?? customer?.name ?? '').trim();
  final shareText = customerName.isEmpty ? number : '$number - $customerName';
  final fileName = customerName.isEmpty
      ? '$number.pdf'
      : '${customerName}_$number.pdf';

  var sharedOrOpened = false;
  // Electron/web open-pdf: dosyayı doğrudan aç. Mobilde _local/open-pdf geçersiz;
  // pdfBase64 veya https URL ile paylaş.
  if (kIsWeb && isLocalOpenPdfUrl(pdfUrl)) {
    sharedOrOpened = await openExternalUrl(pdfUrl);
  } else {
    final shareUrl = isLocalOpenPdfUrl(pdfUrl) ? '' : pdfUrl;
    try {
      sharedOrOpened = await shareEInvoicePdf(
        url: shareUrl,
        fileName: fileName,
        shareText: shareText,
        pdfBase64: pdfBase64,
      );
    } catch (_) {
      // Paylaşım başarısızsa bağlantıyı açmaya geri düşülür.
    }
    if (!sharedOrOpened && shareUrl.trim().isNotEmpty) {
      sharedOrOpened = await openExternalUrl(shareUrl);
    }
  }

  // Electron: Finder’da göster ki kullanıcı sohbete sürükleyebilsin.
  if (kIsWeb) {
    final revealUrl = revealLocalFileUrlFromOpenPdf(pdfUrl);
    if (revealUrl != null) {
      await openExternalUrl(revealUrl);
    }
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        phoneToUse == null
            ? (sharedOrOpened
                  ? 'PDF hazır.'
                  : 'PDF açılamadı; bağlantıyı kontrol edin.')
            : (sharedOrOpened
                  ? 'PDF hazır, WhatsApp sohbetine ekleyin.'
                  : 'WhatsApp açıldı. PDF’i sohbete ekleyin.'),
      ),
      duration: const Duration(seconds: 4),
    ),
  );
}

String buildEInvoiceWhatsAppMessage({
  required Invoice invoice,
  String? customerName,
}) {
  final number = (invoice.eInvoiceNumber?.trim().isNotEmpty ?? false)
      ? invoice.eInvoiceNumber!.trim().replaceFirst(RegExp(r'^\d{9}-'), '')
      : invoice.invoiceNumber.trim();
  final name = (customerName ?? invoice.customerName ?? '').trim();
  final amount = invoice.grandTotal.toStringAsFixed(2);
  final currency = invoice.currency.trim().isEmpty ? 'TRY' : invoice.currency;
  final namePart = name.isEmpty ? '' : ' • $name';
  return 'Microvise E-Fatura • $number$namePart • $amount $currency';
}

String buildInvoicePaymentWhatsAppMessage({
  required String paymentUrl,
  required String amountLabel,
  required List<String> invoiceLabels,
  String? customerName,
  bool includePdfNote = false,
}) {
  final numbers = invoiceLabels
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .join(', ');
  final name = (customerName ?? '').trim();
  final greeting = name.isEmpty ? 'Merhaba,' : 'Merhaba $name,';
  final invoicePart = numbers.isEmpty ? 'faturanız' : numbers;
  final pdfNote = includePdfNote
      ? 'Fatura PDF’si bu mesajla birlikte gönderilir.\n'
      : '';
  return '$greeting\n\n'
      '$invoicePart için sanal POS ödeme linki:\n'
      '$paymentUrl\n\n'
      'Tutar: $amountLabel\n'
      '$pdfNote'
      'Microvise Innovation';
}

/// Cari numaralarından birini seçtirir veya elle numara ister. İptalde null.
Future<String?> pickWhatsAppPhone({
  required BuildContext context,
  CustomerDetail? customer,
  String title = 'WhatsApp ile gönder',
  String subtitle =
      'Numara seçin; WhatsApp sohbeti ödeme linkiyle açılır.',
}) async {
  final options = <_PhoneOption>[];

  void addPhone(String label, String? number) {
    final raw = (number ?? '').trim();
    if (raw.isEmpty) return;
    final normalizedKey = _normalizePhoneKey(raw);
    if (normalizedKey.isEmpty) return;
    if (options.any((o) => _normalizePhoneKey(o.phone) == normalizedKey)) {
      return;
    }
    options.add(_PhoneOption(label: label, phone: raw));
  }

  if (customer != null) {
    _addCustomerPhones(addPhone, customer);
  }

  final action = await showModalBottomSheet<_ShareAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Gap(6),
            Text(
              options.isEmpty
                  ? 'Cariye kayıtlı numara yok. Numara girin veya vazgeçin.'
                  : subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            ),
            const Gap(12),
            for (final opt in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.messageCircle),
                title: Text(opt.label),
                subtitle: Text(opt.phone),
                onTap: () =>
                    Navigator.of(context).pop(_ShareAction.whatsApp(opt.phone)),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.phoneCall),
              title: const Text('Başka numara'),
              onTap: () =>
                  Navigator.of(context).pop(const _ShareAction.other()),
            ),
          ],
        ),
      ),
    ),
  );

  if (action == null) return null;
  if (action.kind == _ShareActionKind.other) {
    if (!context.mounted) return null;
    return _askPhoneNumber(context);
  }
  if (action.kind == _ShareActionKind.whatsapp) {
    return action.phone;
  }
  return null;
}

Future<void> shareInvoicePaymentLinkWithWhatsApp({
  required BuildContext context,
  required String paymentUrl,
  required String amountLabel,
  required List<String> invoiceLabels,
  String? customerName,
  CustomerDetail? customer,
  List<EInvoicePdfDownload> pdfs = const [],
}) async {
  final phone = await pickWhatsAppPhone(
    context: context,
    customer: customer,
    title: 'Ödeme linkini WhatsApp ile gönder',
    subtitle: pdfs.isEmpty
        ? 'Numara seçin; WhatsApp sohbeti ödeme linki mesajıyla açılır.'
        : 'Numara seçin; WhatsApp sohbeti ödeme linki ve fatura PDF’siyle açılır.',
  );
  if (phone == null || !context.mounted) return;

  final message = buildInvoicePaymentWhatsAppMessage(
    paymentUrl: paymentUrl,
    amountLabel: amountLabel,
    invoiceLabels: invoiceLabels,
    customerName: customerName ?? customer?.name,
    includePdfNote: pdfs.isNotEmpty,
  );
  await Clipboard.setData(ClipboardData(text: message));

  final waPhone = normalizePhoneForWhatsApp(phone);
  final url = waPhone.isEmpty
      ? Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}')
      : Uri.parse(
          'https://wa.me/$waPhone?text=${Uri.encodeComponent(message)}',
        );
  final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!opened) {
    await openExternalUrl(url.toString());
  }

  var sharedPdf = false;
  if (pdfs.isNotEmpty) {
    try {
      sharedPdf = await shareEInvoicePdfBundle(
        files: pdfs,
        shareText: message,
      );
    } catch (_) {
      sharedPdf = false;
    }
    if (!sharedPdf) {
      for (final pdf in pdfs) {
        if (kIsWeb && isLocalOpenPdfUrl(pdf.url)) {
          sharedPdf = await openExternalUrl(pdf.url) || sharedPdf;
          continue;
        }
        if (pdf.url.trim().isNotEmpty && !isLocalOpenPdfUrl(pdf.url)) {
          sharedPdf = await openExternalUrl(pdf.url) || sharedPdf;
        }
      }
    }
    if (kIsWeb) {
      for (final pdf in pdfs) {
        final revealUrl = revealLocalFileUrlFromOpenPdf(pdf.url);
        if (revealUrl != null) {
          await openExternalUrl(revealUrl);
        }
      }
    }
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        sharedPdf
            ? 'WhatsApp açıldı. Fatura PDF’sini sohbete ekleyin.'
            : 'WhatsApp açıldı. Ödeme linki sohbete yazıldı.',
      ),
    ),
  );
}

/// TR (+90) ve Kıbrıs (+357 / KKTC 053x→90) numaralarını wa.me için normalize eder.
String normalizePhoneForWhatsApp(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('90') && digits.length >= 12) return digits;
  if (digits.startsWith('357') && digits.length >= 11) return digits;
  // KKTC / TR mobil: 05xx… → 905xx…
  if (digits.length == 11 && digits.startsWith('0')) {
    return '90${digits.substring(1)}';
  }
  // 10 haneli yerel (5xx… TR/KKTC veya 9xxxxxx CY)
  if (digits.length == 10) {
    if (digits.startsWith('5')) return '90$digits';
    return '357$digits';
  }
  // Güney Kıbrıs 8 haneli yerel
  if (digits.length == 8) return '357$digits';
  return digits;
}

/// `/api/_local/open-pdf?path=` URL’sinden Finder reveal URL’si üretir.
String? revealLocalFileUrlFromOpenPdf(String pdfUrl) {
  final uri = Uri.tryParse(pdfUrl);
  if (uri == null) return null;
  if (!_isLocalOpenPdfPath(uri.path)) return null;
  final filePath = uri.queryParameters['path']?.trim() ?? '';
  if (filePath.isEmpty) return null;
  return uri
      .replace(
        path: '/api/_local/reveal-file',
        queryParameters: {'path': filePath},
      )
      .toString();
}

bool isLocalOpenPdfUrl(String pdfUrl) {
  final uri = Uri.tryParse(pdfUrl.trim());
  if (uri == null) return false;
  return _isLocalOpenPdfPath(uri.path) &&
      (uri.queryParameters['path']?.trim().isNotEmpty ?? false);
}

bool _isLocalOpenPdfPath(String path) => path == '/api/_local/open-pdf';

Future<String?> _askPhoneNumber(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String?>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('WhatsApp Numara'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Numara',
          hintText: 'Örn: +90533... veya 0533...',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Devam'),
        ),
      ],
    ),
  );
  controller.dispose();
  final phone = (result ?? '').trim();
  if (phone.isEmpty) return null;
  return phone;
}

String _normalizePhoneKey(String raw) {
  return raw.replaceAll(RegExp(r'[^0-9]'), '');
}

class _PhoneOption {
  const _PhoneOption({required this.label, required this.phone});
  final String label;
  final String phone;
}

enum _ShareActionKind { whatsapp, other, openPdfOnly }

class _ShareAction {
  const _ShareAction._(this.kind, {this.phone});
  final _ShareActionKind kind;
  final String? phone;

  const _ShareAction.other() : this._(_ShareActionKind.other);
  const _ShareAction.openPdfOnly() : this._(_ShareActionKind.openPdfOnly);
  const _ShareAction.whatsApp(String phone)
    : this._(_ShareActionKind.whatsapp, phone: phone);
}
