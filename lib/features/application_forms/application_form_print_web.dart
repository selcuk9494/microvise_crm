// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'application_form_model.dart';

enum ApplicationPrintKind { kdv, kdv4a }

extension ApplicationPrintKindLabel on ApplicationPrintKind {
  String get label => this == ApplicationPrintKind.kdv ? 'KDV' : 'KDV4A';
}

Future<bool> printApplicationForm(
  ApplicationFormRecord record, {
  required ApplicationPrintKind kind,
}) async {
  final title = kind.label;
  final htmlContent = _buildPrintableHtml(record, title: title);
  final dataUrl = Uri.dataFromString(
    htmlContent,
    mimeType: 'text/html',
    encoding: utf8,
  ).toString();
  html.window.open(dataUrl, '_blank');
  return true;
}

String _buildPrintableHtml(
  ApplicationFormRecord record, {
  required String title,
}) {
  String escape(String? value, String fallback) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return fallback;
    return const HtmlEscape(HtmlEscapeMode.element).convert(text);
  }

  final applicationDate =
      '${record.applicationDate.day.toString().padLeft(2, '0')}.${record.applicationDate.month.toString().padLeft(2, '0')}.${record.applicationDate.year}';
  final okcDate = record.okcStartDate == null
      ? '[4]'
      : '${record.okcStartDate!.day.toString().padLeft(2, '0')}.${record.okcStartDate!.month.toString().padLeft(2, '0')}.${record.okcStartDate!.year}';

  final rows = [
    (
      "Satışa Ait Faturanın Tarihi ve No'su",
      '${escape(applicationDate, '[1]')} / ${escape(record.invoiceNumber, '[1]')}',
    ),
    ('Adı - Soyadı / Ünvanı', escape(record.customerName, '[2]')),
    ('İşyeri Adresi', escape(record.workAddress, '[3]')),
    ('Bağlı Olduğu Vergi Dairesi', escape(record.taxOfficeCityName, '[4]')),
    ('Türü', escape(record.documentType, 'VKN')),
    ('Dosya Sicil No', escape(record.fileRegistryNumber, '[5]')),
    ('Cihazın Çalıştırılma Tarihi', escape(applicationDate, '[6]')),
    ('Direktör', escape(record.director, '[7]')),
    ('Markası ve Modeli', escape(record.brandModel, '[8]')),
    ('Cihaz Sicil No', escape(record.stockRegistryNumber, '[9]')),
    ('Mali Sembol ve Firma Kodu', escape(record.fiscalSymbolName, '[10]')),
    ('Muhasebe Ofisi', escape(record.accountingOffice, '[11]')),
    ('ÖKC Kullanmaya Başlama Tarihi', escape(okcDate, '[12]')),
    (
      'Ticari Faaliyet / Meslek Türü',
      escape(record.businessActivityName, '[13]'),
    ),
    ('Fatura No', escape(record.invoiceNumber, '[14]')),
  ];

  final rowsHtml = rows
      .map(
        (row) =>
            '''
          <tr>
            <td class="label">${row.$1}</td>
            <td class="value">${row.$2}</td>
          </tr>
        ''',
      )
      .join();

  return '''
<!doctype html>
<html lang="tr">
  <head>
    <meta charset="utf-8">
    <title>$title</title>
    <script>
      window.onload = function() {
        setTimeout(function() { window.print(); }, 250);
      };
    </script>
    <style>
      body {
        font-family: Arial, sans-serif;
        margin: 24px;
        color: #111827;
      }
      h1 {
        margin: 0 0 14px;
        font-size: 22px;
      }
      table {
        width: 100%;
        border-collapse: collapse;
      }
      td {
        border: 1px solid #1f2937;
        padding: 6px 8px;
        vertical-align: top;
        font-size: 14px;
      }
      .label {
        width: 42%;
        background: #ffef5f;
        font-weight: 700;
        color: #111827;
      }
      .value {
        width: 58%;
        color: #111827;
        font-weight: 600;
      }
      .note {
        margin-top: 12px;
        color: #6b7280;
        font-size: 12px;
      }
    </style>
  </head>
  <body>
    <h1>$title</h1>
    <table>$rowsHtml</table>
    <div class="note">Numaralı alanlar netleştirilecek sabit alan placeholder'larıdır.</div>
  </body>
</html>
''';
}

class HtmlEscape {
  const HtmlEscape([this.mode = HtmlEscapeMode.unknown]);

  final HtmlEscapeMode mode;

  String convert(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}

class HtmlEscapeMode {
  const HtmlEscapeMode._();

  static const element = HtmlEscapeMode._();
  static const unknown = HtmlEscapeMode._();
}
