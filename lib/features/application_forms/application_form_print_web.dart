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
  final htmlContent = _buildPrintableHtml(record, kind: kind);
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
  required ApplicationPrintKind kind,
}) {
  String escape(String? value) {
    return const HtmlEscape(
      HtmlEscapeMode.element,
    ).convert((value ?? '').trim());
  }

  String withPlaceholder(String? value, String fallback) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return '<span class="placeholder">$fallback</span>';
    }
    return escape(text);
  }

  String dottedValue(
    String? value, {
    String fallback = '',
    bool fixed = false,
    String extraClass = '',
  }) {
    final text = (value ?? '').trim();
    final hasValue = text.isNotEmpty;
    final klass = [
      'dotted',
      if (fixed) 'fixed',
      if (!hasValue) 'empty',
      if (extraClass.isNotEmpty) extraClass,
    ].join(' ');
    return '<span class="$klass">${hasValue ? escape(text) : fallback}</span>';
  }

  String formatDate(DateTime? value, {String fallback = ''}) {
    if (value == null) return fallback;
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  final ownerName = (record.director ?? '').trim().isNotEmpty
      ? record.director!.trim()
      : record.customerName.trim();
  final directorName = (record.director ?? '').trim().isNotEmpty
      ? record.director!.trim()
      : ownerName;
  final applicationDate = formatDate(record.applicationDate);
  final okcDate = formatDate(record.okcStartDate, fallback: '[1]');
  final formCode = kind == ApplicationPrintKind.kdv
      ? '(Forma. KDV 4)'
      : '(Forma. KDV 4A)';
  final formLabel = kind.label;

  final bodyHtml = kind == ApplicationPrintKind.kdv
      ? _buildKdvBody(
          record: record,
          ownerName: ownerName,
          directorName: directorName,
          applicationDate: applicationDate,
          okcDate: okcDate,
          dottedValue: dottedValue,
          withPlaceholder: withPlaceholder,
        )
      : _buildKdvBody(
          record: record,
          ownerName: ownerName,
          directorName: directorName,
          applicationDate: applicationDate,
          okcDate: okcDate,
          dottedValue: dottedValue,
          withPlaceholder: withPlaceholder,
        );

  return '''
<!doctype html>
<html lang="tr">
  <head>
    <meta charset="utf-8">
    <title>$formLabel</title>
    <script>
      window.onload = function() {
        setTimeout(function() { window.print(); }, 250);
      };
    </script>
    <style>
      @page {
        size: A4 portrait;
        margin: 12mm;
      }
      body {
        margin: 0;
        background: #fff;
        color: #000;
        font-family: Arial, Helvetica, sans-serif;
      }
      .sheet {
        width: 820px;
        margin: 0 auto;
        padding: 10px 8px 24px;
      }
      .top-code {
        text-align: right;
        font-size: 16px;
        margin: 6px 0 18px;
      }
      .title {
        text-align: center;
        font-weight: 700;
        font-size: 24px;
        margin: 6px 0 22px;
      }
      .top-meta {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        margin-bottom: 26px;
      }
      .office {
        font-size: 22px;
        font-weight: 700;
        line-height: 1.35;
        white-space: pre-line;
      }
      .date-row {
        display: flex;
        align-items: baseline;
        gap: 16px;
        font-size: 22px;
        font-weight: 700;
      }
      .intro {
        font-size: 18px;
        line-height: 1.58;
        margin: 0 0 26px;
        max-width: 92%;
      }
      .line {
        display: flex;
        align-items: baseline;
        gap: 8px;
        font-size: 18px;
        line-height: 1.45;
        margin: 2px 0;
      }
      .indent-1 { padding-left: 20px; }
      .indent-2 { padding-left: 54px; }
      .indent-3 { padding-left: 90px; }
      .label {
        white-space: pre-wrap;
      }
      .colon {
        min-width: 10px;
        font-weight: 700;
      }
      .dotted {
        display: inline-block;
        min-width: 120px;
        border-bottom: 2px dotted #333;
        padding: 0 4px 1px;
        line-height: 1.1;
      }
      .grow {
        flex: 1;
      }
      .wide { min-width: 540px; }
      .medium { min-width: 360px; }
      .short { min-width: 180px; }
      .fixed {
        font-weight: 400;
      }
      .placeholder {
        color: #b91c1c;
        font-weight: 700;
      }
      .signature-block {
        width: 340px;
        margin-left: auto;
        margin-top: 54px;
      }
      .signature-title {
        font-size: 18px;
        font-weight: 700;
        display: inline-block;
        border-bottom: 4px solid #000;
        padding: 0 4px 2px;
        margin-bottom: 16px;
      }
      .signature-line {
        display: flex;
        align-items: baseline;
        gap: 8px;
        font-size: 18px;
        margin: 14px 0;
      }
      .print-kind {
        position: absolute;
        top: 6px;
        right: 22px;
        color: #b91c1c;
        font-size: 18px;
        font-weight: 700;
      }
      .page {
        position: relative;
      }
    </style>
  </head>
  <body>
    <div class="sheet page">
      <div class="print-kind">$formLabel</div>
      <div class="top-code">$formCode</div>
      <div class="title">ÖDEME KAYDEDİCİ CİHAZ ONAY TALEP FORMU</div>
      $bodyHtml
    </div>
  </body>
</html>
''';
}

String _buildKdvBody({
  required ApplicationFormRecord record,
  required String ownerName,
  required String directorName,
  required String applicationDate,
  required String okcDate,
  required String Function(
    String? value, {
    String fallback,
    bool fixed,
    String extraClass,
  })
  dottedValue,
  required String Function(String? value, String fallback) withPlaceholder,
}) {
  final businessName = withPlaceholder(record.customerName, '[1]');
  final workAddress = withPlaceholder(record.workAddress, '[2]');
  final accountant = dottedValue(record.accountingOffice, fallback: '');
  final businessActivity = withPlaceholder(record.businessActivityName, '[3]');
  final brand = withPlaceholder(record.brandName, '[4]');
  final model = withPlaceholder(record.modelName, '[5]');
  final stockRegistry = withPlaceholder(record.stockRegistryNumber, '[6]');
  final sellerCompany = 'MICROVISE INNOVATION LTD.';
  final sellerAddress = 'Atatürk Cad Emek 2 No:1 Yenişehir Lefkoşa';

  return '''
<div class="top-meta">
  <div class="office">Maliye Bakanlığı
Gelir ve Vergi Dairesi
LEFKOŞA</div>
  <div class="date-row">
    <span>Tarih :</span>
    ${dottedValue(applicationDate, extraClass: 'short')}
  </div>
</div>

<p class="intro">
  47/1992 Sayılı Katma Değer Vergisi Yazası' nın 53' üncü maddesi uyarınca işletmemizin
  Ödeme Kaydedici Cihaz kullanma zorunluluğunun yerine getirilebilmesi için aşağıdaki hususları
  beyan eder, gerekli onayın verilmesini rica ederim.
</p>

<div class="line">
  <span class="label">1-İşletmenin Ünvanı</span>
  <span class="colon">:</span>
  ${dottedValue(businessName, extraClass: 'grow')}
</div>
<div class="line indent-1">
  <span class="label">a) İşletmenin Sahibi</span>
  <span class="colon">:</span>
  ${dottedValue(ownerName, extraClass: 'grow')}
</div>
<div class="line indent-1">
  <span class="label">b) İşletmenin Direktörü</span>
  <span class="colon">:</span>
  ${dottedValue(directorName, extraClass: 'grow')}
</div>
<div class="line">
  <span class="label">2-İşletmenin Merkez Adresi</span>
  <span class="colon">:</span>
  ${dottedValue(workAddress, extraClass: 'grow')}
</div>
<div class="line indent-1">
  <span class="label">Varsa Şubelerinin Adresi</span>
  <span class="colon">:</span>
  ${dottedValue('', fallback: '', extraClass: 'grow')}
</div>
<div class="line">
  <span class="label">3-İşletmenin Muhasip - Murakkıbı</span>
  <span class="colon">:</span>
  ${accountant.replaceFirst('class="dotted', 'class="dotted grow')}
</div>
<div class="line">
  <span class="label">4-Ödeme Kaydedici Cihaz Kullanmaya Başlama Tarihi</span>
  <span class="colon">:</span>
  ${dottedValue(okcDate, extraClass: 'grow')}
</div>
<div class="line">
  <span class="label">5-Ticari Faaliyet / Meslek Türü</span>
  <span class="colon">:</span>
  ${dottedValue(businessActivity, extraClass: 'grow')}
</div>
<div class="line">
  <span class="label">6-Kullanılacak Ödeme Kaydedici Cihazın</span>
  <span class="colon">:</span>
</div>
<div class="line indent-1">
  <span class="label">a) Markası</span>
  <span class="colon">:</span>
  ${dottedValue(brand, extraClass: 'grow')}
</div>
<div class="line indent-1">
  <span class="label">b) Modeli</span>
  <span class="colon">:</span>
  ${dottedValue(model, extraClass: 'medium')}
  <span class="label">Sicil No</span>
  <span class="colon">:</span>
  ${dottedValue(stockRegistry, extraClass: 'medium')}
</div>
<div class="line indent-1">
  <span class="label">c) Güç Kaynağı ile ilgili Önlemler</span>
  <span class="colon">:</span>
  ${dottedValue('Opsiyonel', fixed: true, extraClass: 'grow')}
</div>
<div class="line">
  <span class="label">7-Ekte Sunulacak Evraklar</span>
  <span class="colon">:</span>
  ${dottedValue('', fallback: '', extraClass: 'grow')}
</div>
<div class="line indent-1">
  <span class="label">X  a) Genel Kullanım Kılavuzu</span>
  <span class="colon">:</span>
  ${dottedValue('Var', fixed: true, extraClass: 'grow')}
</div>
<div class="line indent-1">
  <span class="label">b) Satıcı ile Bakım ve Onarım işlemlerini yapmayı taahhüt eden firmanın :</span>
</div>
<div class="line indent-2">
  <span class="label">Adı - Soyadı</span>
  <span class="colon">:</span>
  ${dottedValue(sellerCompany, fixed: true, extraClass: 'grow')}
</div>
<div class="line indent-2">
  <span class="label">Adresi</span>
  <span class="colon">:</span>
  ${dottedValue(sellerAddress, fixed: true, extraClass: 'grow')}
</div>

<div class="signature-block">
  <div class="signature-title">BAŞVURU SAHİBİNİN :</div>
  <div class="signature-line">
    <span class="label">Adı - Soyadı</span>
    <span class="colon">:</span>
    ${dottedValue(ownerName, extraClass: 'grow')}
  </div>
  <div class="signature-line">
    <span class="label">İmzası</span>
    <span class="colon">:</span>
    ${dottedValue('', fallback: '', extraClass: 'grow')}
  </div>
  <div class="signature-line">
    <span class="label">Statüsü</span>
    <span class="colon">:</span>
    ${dottedValue('DİREKTÖR', fixed: true, extraClass: 'grow')}
  </div>
</div>
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
