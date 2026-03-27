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
  final bytes = utf8.encode(htmlContent);
  final blob = html.Blob([bytes], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future<void>.delayed(const Duration(seconds: 5), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}

String _buildPrintableHtml(
  ApplicationFormRecord record, {
  required String title,
}) {
  String escape(String? value, String fallback) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return '<span class="placeholder">$fallback</span>';
    }
    return const HtmlEscape(HtmlEscapeMode.element).convert(text);
  }

  String fixed(String value) {
    return '<span class="fixed-value">${const HtmlEscape(HtmlEscapeMode.element).convert(value)}</span>';
  }

  final applicationDate =
      '${record.applicationDate.day.toString().padLeft(2, '0')}.${record.applicationDate.month.toString().padLeft(2, '0')}.${record.applicationDate.year}';
  final okcDate = record.okcStartDate == null
      ? '[4]'
      : '${record.okcStartDate!.day.toString().padLeft(2, '0')}.${record.okcStartDate!.month.toString().padLeft(2, '0')}.${record.okcStartDate!.year}';

  final rows = [
    (
      "Satışa Ait faturanın Tarih ve No' su",
      '${escape(applicationDate, '[1]')} / ${escape(record.invoiceNumber, '[1]')}',
    ),
    ('Adı - Soyadı / Ünvanı', escape(record.customerName, '[2]')),
    ('İşyeri Adresi', escape(record.workAddress, '[3]')),
    ('Bağlı olduğu Vergi Dairesi', escape(record.taxOfficeCityName, '[4]')),
    (
      'Türü',
      fixed(record.documentType.trim().isEmpty ? 'VKN' : record.documentType),
    ),
    ('Dosya Sicil No', escape(record.fileRegistryNumber, '[5]')),
    ('Cihazın çalıştırılma Tarihi', escape(applicationDate, '[6]')),
    ('Direktör', escape(record.director, '[7]')),
    ('Markası ve Modeli', escape(record.brandModel, '[8]')),
    ('Cihaz Sicil No', escape(record.stockRegistryNumber, '[9]')),
    ('Mali Sembol ve Firma Kodu', escape(record.fiscalSymbolName, '[10]')),
    ('Muhasebe Ofisi', escape(record.accountingOffice, '[11]')),
    ('Ökc Kullanmaya başlama Tarihi', escape(okcDate, '[12]')),
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
      @page {
        size: A4 portrait;
        margin: 10mm;
      }
      body {
        font-family: Arial, Helvetica, sans-serif;
        margin: 0;
        color: #000;
        background: #fff;
      }
      .sheet {
        width: 760px;
        margin: 0 auto;
      }
      .sheet-head {
        display: flex;
        justify-content: flex-end;
        margin-bottom: 6px;
        font-size: 12px;
        font-weight: 700;
        color: #b91c1c;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        table-layout: fixed;
      }
      td {
        border: 1px solid #000;
        padding: 3px 6px;
        vertical-align: middle;
        font-size: 12px;
        line-height: 1.15;
      }
      .label {
        width: 42.5%;
        background: #fff15c;
        font-weight: 700;
        color: #000;
      }
      .value {
        width: 57.5%;
        color: #000;
        font-weight: 500;
        word-break: break-word;
      }
      .fixed-value {
        color: #b91c1c;
        font-weight: 700;
      }
      .placeholder {
        color: #b91c1c;
        font-weight: 700;
      }
    </style>
  </head>
  <body>
    <div class="sheet">
      <div class="sheet-head">$title</div>
      <table>$rowsHtml</table>
    </div>
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
