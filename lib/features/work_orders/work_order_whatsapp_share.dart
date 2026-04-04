import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../customers/customer_detail_screen.dart';
import 'work_order_model.dart';
import 'work_order_share.dart';

Future<void> shareWorkOrderPdfWithWhatsAppPrompt({
  required BuildContext context,
  required WorkOrder order,
  required CustomerDetail customer,
  required String? closeNotes,
  required List<WorkOrderPayment> payments,
  Uint8List? signaturePngBytes,
  Uint8List? personnelSignaturePngBytes,
}) async {
  final options = <_PhoneOption>[];

  void addPhone(String label, String? number) {
    final raw = (number ?? '').trim();
    if (raw.isEmpty) return;
    final normalizedKey = _normalizePhoneKey(raw);
    if (normalizedKey.isEmpty) return;
    if (options.any((o) => _normalizePhoneKey(o.phone) == normalizedKey)) return;
    options.add(_PhoneOption(label: label, phone: raw));
  }

  addPhone((customer.phone1Title ?? 'Müşteri').trim().isEmpty ? 'Müşteri' : customer.phone1Title!, customer.phone1);
  addPhone((customer.phone2Title ?? 'İrtibat').trim().isEmpty ? 'İrtibat' : customer.phone2Title!, customer.phone2);
  addPhone((customer.phone3Title ?? 'İrtibat 2').trim().isEmpty ? 'İrtibat 2' : customer.phone3Title!, customer.phone3);
  addPhone('İş Emri İrtibat', order.contactPhone);

  final action = await showModalBottomSheet<_ShareAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PDF Paylaş', style: Theme.of(context).textTheme.titleMedium),
            const Gap(6),
            Text(
              'WhatsApp ile göndermek için bir numara seçin veya sadece paylaşın.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
            ),
            const Gap(12),
            for (final opt in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat_bubble_rounded),
                title: Text(opt.label),
                subtitle: Text(opt.phone),
                onTap: () => Navigator.of(context).pop(
                  _ShareAction.whatsApp(opt.phone),
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_call),
              title: const Text('Başka numara'),
              onTap: () => Navigator.of(context).pop(const _ShareAction.other()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.share_rounded),
              title: const Text('Sadece paylaş'),
              onTap: () => Navigator.of(context).pop(const _ShareAction.shareOnly()),
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

  final message = _buildWhatsAppMessage(order: order, customer: customer);
  await Clipboard.setData(ClipboardData(text: message));

  if (phoneToUse != null) {
    final waPhone = _normalizeForWhatsApp(phoneToUse);
    if (waPhone.isNotEmpty) {
      final url = Uri.parse(
        'https://wa.me/$waPhone?text=${Uri.encodeComponent(message)}',
      );
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  await shareWorkOrderPdf(
    order: order,
    customer: customer,
    closeNotes: closeNotes,
    payments: payments,
    signaturePngBytes: signaturePngBytes,
    personnelSignaturePngBytes: personnelSignaturePngBytes,
  );
}

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

String _buildWhatsAppMessage({required WorkOrder order, required CustomerDetail customer}) {
  final docNo = order.id.length >= 6 ? order.id.substring(0, 6) : order.id;
  final title = order.title.trim().isEmpty ? 'İş Emri' : order.title.trim();
  return 'Microvise Servis Formu • Form No: $docNo • ${customer.name.trim()} • $title';
}

String _normalizePhoneKey(String raw) {
  return raw.replaceAll(RegExp(r'[^0-9]'), '');
}

String _normalizeForWhatsApp(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) {
    digits = '90${digits.substring(1)}';
  } else if (digits.length == 10) {
    digits = '90$digits';
  }
  return digits;
}

class _PhoneOption {
  const _PhoneOption({required this.label, required this.phone});
  final String label;
  final String phone;
}

enum _ShareActionKind { whatsapp, other, shareOnly }

class _ShareAction {
  const _ShareAction._(this.kind, {this.phone});
  final _ShareActionKind kind;
  final String? phone;

  const _ShareAction.other() : this._(_ShareActionKind.other);
  const _ShareAction.shareOnly() : this._(_ShareActionKind.shareOnly);
  const _ShareAction.whatsApp(String phone)
      : this._(_ShareActionKind.whatsapp, phone: phone);
}
