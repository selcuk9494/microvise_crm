// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'application_form_model.dart';

enum ApplicationPrintKind { kdv, kdv4a }

extension ApplicationPrintKindLabel on ApplicationPrintKind {
  String get label => this == ApplicationPrintKind.kdv ? 'KDV4' : 'KDV4A';
}

Future<bool> printApplicationForm(
  ApplicationFormRecord record, {
  required ApplicationPrintKind kind,
  ApplicationFormPrintSettings? settings,
}) async {
  final htmlContent = _buildPrintableHtml(
    record,
    kind: kind,
    settings: settings ?? ApplicationFormPrintSettings.defaults,
  );
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future<void>.delayed(const Duration(seconds: 30), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}

String _buildPrintableHtml(
  ApplicationFormRecord record, {
  required ApplicationPrintKind kind,
  required ApplicationFormPrintSettings settings,
}) {
  String escape(String? value) {
    return (html.DivElement()..text = (value ?? '').trim()).innerHtml ?? '';
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
  final bodyHtml = kind == ApplicationPrintKind.kdv
      ? _buildKdvBody(
          record: record,
          settings: settings,
          escape: escape,
          ownerName: ownerName,
          directorName: directorName,
          applicationDate: applicationDate,
          okcDate: okcDate,
          dottedValue: dottedValue,
          withPlaceholder: withPlaceholder,
        )
      : _buildKdv4aBody(
          record: record,
          settings: settings,
          escape: escape,
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
    <title></title>
    <script>
      window.onload = function() {
        setTimeout(function() { window.print(); }, 250);
      };
    </script>
    <style>
      @page {
        size: A4 portrait;
        margin: 5mm;
      }
      body {
        margin: 0;
        background: #fff;
        color: #000;
        font-family: Arial, Helvetica, sans-serif;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }
      .sheet {
        width: 700px;
        margin: 0 auto;
        padding: 2px 2px 8px;
      }
      .sheet.kdv {
        width: 760px;
        padding: 6px 8px 12px;
      }
      .top-code {
        text-align: right;
        font-size: 12px;
        margin: 1px 0 6px;
      }
      .title {
        text-align: center;
        font-weight: 700;
        font-size: 18px;
        margin: 1px 0 8px;
        white-space: pre-line;
      }
      .office {
        font-size: 15px;
        font-weight: 700;
        line-height: 1.2;
        white-space: pre-line;
        margin-bottom: 8px;
      }
      .intro {
        font-size: 13px;
        line-height: 1.28;
        margin: 0 0 10px;
        max-width: 92%;
      }
      .line {
        display: flex;
        align-items: baseline;
        flex-wrap: nowrap;
        gap: 5px;
        font-size: 13px;
        line-height: 1.16;
        margin: 1px 0;
      }
      .indent-1 { padding-left: 14px; }
      .indent-2 { padding-left: 36px; }
      .indent-3 { padding-left: 64px; }
      .label {
        white-space: pre-wrap;
      }
      .colon {
        min-width: 10px;
        font-weight: 700;
      }
      .dotted {
        display: inline-block;
        min-width: 90px;
        border-bottom: 1px dotted #333;
        padding: 0 4px 1px;
        line-height: 1.1;
      }
      .grow {
        flex: 1;
      }
      .wide { min-width: 470px; }
      .medium { min-width: 300px; }
      .short { min-width: 140px; }
      .flex-none { flex: 0 0 auto; }
      .fixed {
        font-weight: 400;
      }
      .placeholder {
        color: #b91c1c;
        font-weight: 700;
      }
      .signature-block {
        width: 300px;
        margin-left: auto;
        margin-top: 28px;
      }
      .signature-title {
        font-size: 14px;
        font-weight: 700;
        display: inline-block;
        border-bottom: 3px solid #000;
        padding: 0 4px 2px;
        margin-bottom: 8px;
      }
      .signature-line {
        display: flex;
        align-items: baseline;
        gap: 8px;
        font-size: 13px;
        margin: 6px 0;
      }
      .underline-title {
        display: inline-block;
        border-bottom: 3px solid #000;
        padding-bottom: 2px;
        font-weight: 700;
      }
      .box {
        border: 3px solid #000;
        padding: 6px 10px;
        width: 470px;
        margin: 8px auto 6px;
      }
      .box-title {
        text-align: center;
        font-size: 14px;
        margin-bottom: 8px;
      }
      .notice {
        font-size: 12px;
        line-height: 1.2;
        margin: 6px 4px 8px;
        text-align: center;
      }
      .dual-sign {
        display: flex;
        justify-content: space-between;
        gap: 20px;
        margin-top: 4px;
      }
      .dual-col {
        width: 48%;
      }
      .dual-col .head {
        font-size: 14px;
        font-weight: 700;
        margin-bottom: 4px;
        white-space: pre-line;
      }
      .mini-line {
        display: flex;
        align-items: baseline;
        gap: 8px;
        font-size: 14px;
        margin: 4px 0;
      }
      .page {
        position: relative;
      }
      .sheet.kdv .top-code {
        margin-bottom: 10px;
      }
      .sheet.kdv .title {
        font-size: 20px;
        margin: 4px 0 12px;
      }
      .sheet.kdv .office {
        font-size: 16px;
        line-height: 1.25;
        margin-bottom: 10px;
      }
      .sheet.kdv .intro {
        font-size: 14px;
        line-height: 1.38;
        margin-bottom: 12px;
        max-width: 95%;
      }
      .sheet.kdv .line {
        gap: 7px;
        font-size: 14px;
        line-height: 1.24;
        margin: 3px 0;
      }
      .sheet.kdv .indent-1 { padding-left: 18px; }
      .sheet.kdv .indent-2 { padding-left: 42px; }
      .sheet.kdv .dotted {
        min-width: 120px;
        padding: 0 5px 2px;
      }
      .sheet.kdv .wide { min-width: 520px; }
      .sheet.kdv .medium { min-width: 340px; }
      .sheet.kdv .short { min-width: 170px; }
      .sheet.kdv .signature-block {
        width: 340px;
        margin-top: 30px;
      }
      .sheet.kdv .signature-title {
        font-size: 15px;
        margin-bottom: 10px;
      }
      .sheet.kdv .signature-line {
        font-size: 14px;
        margin: 7px 0;
      }
    </style>
  </head>
  <body>
    <div class="sheet page ${kind == ApplicationPrintKind.kdv ? 'kdv' : 'kdv4a'}">
      <div class="top-code">$formCode</div>
      <div class="title">${escape(kind == ApplicationPrintKind.kdv ? 'ÖDEME KAYDEDİCİ CİHAZ ONAY TALEP FORMU' : settings.kdv4aTitle)}</div>
      $bodyHtml
    </div>
  </body>
</html>
''';
}

String _buildKdvBody({
  required ApplicationFormRecord record,
  required ApplicationFormPrintSettings settings,
  required String Function(String? value) escape,
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
  final businessName = record.customerName;
  final workAddress = record.workAddress;
  final accountant = dottedValue(record.accountingOffice, fallback: '');
  final businessActivity = record.businessActivityName;
  final brand = record.brandName;
  final model = record.modelName;
  final stockRegistry = record.stockRegistryNumber;
  final sellerCompany = settings.serviceCompanyName;
  final sellerAddress = settings.serviceCompanyAddress;

  return '''
<div class="office">${escape(settings.officeTitle).replaceAll('\n', '<br>')}</div>

<p class="intro">
  ${escape(settings.introText)}
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
  ${dottedValue(model, extraClass: 'short flex-none')}
  <span class="label flex-none">Sicil No</span>
  <span class="colon">:</span>
  ${dottedValue(stockRegistry, extraClass: 'medium grow')}
</div>
<div class="line indent-1">
  <span class="label">c) Güç Kaynağı ile ilgili Önlemler</span>
  <span class="colon">:</span>
  ${dottedValue(settings.optionalPowerPrecautionText, fixed: true, extraClass: 'grow')}
</div>
<div class="line">
  <span class="label">7-Ekte Sunulacak Evraklar</span>
  <span class="colon">:</span>
  ${dottedValue('', fallback: '', extraClass: 'grow')}
</div>
<div class="line indent-1">
  <span class="label">X  a) Genel Kullanım Kılavuzu</span>
  <span class="colon">:</span>
  ${dottedValue(settings.manualIncludedText, fixed: true, extraClass: 'grow')}
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
    ${dottedValue(settings.applicantStatus, fixed: true, extraClass: 'grow')}
  </div>
</div>
''';
}

String _buildKdv4aBody({
  required ApplicationFormRecord record,
  required ApplicationFormPrintSettings settings,
  required String Function(String? value) escape,
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
  final businessName = record.customerName;
  final workAddress = record.workAddress;
  final buyerTaxRegistry =
      '${record.taxOfficeCityName ?? ''} ${record.documentType}: ${record.fileRegistryNumber ?? ''}';
  final brand = record.brandName;
  final model = record.modelName;
  final stockRegistry = record.stockRegistryNumber;
  final fiscalSymbol = record.fiscalSymbolName;

  return '''
<div class="line" style="justify-content:flex-end; margin-bottom: 6px;">
  <span class="label" style="font-weight:700;">Sıra No. :</span>
  ${dottedValue(settings.kdv4aSerialNumber, extraClass: 'medium')}
</div>

<div class="office">${escape(settings.officeTitle4a).replaceAll('\n', '<br>')}</div>

<div class="line"><span class="label" style="font-weight:700;">1- CİHAZI SATAN KİŞİ VEYA İŞLETMENİN</span></div>
<div class="line indent-1"><span class="label">-- Adı - Soyadı / Ünvanı</span><span class="colon">:</span>${dottedValue(settings.kdv4aSellerCompanyName, fixed: true, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- İşyeri Adresi</span><span class="colon">:</span>${dottedValue(settings.kdv4aSellerAddress, fixed: true, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No</span><span class="colon">:</span>${dottedValue(settings.kdv4aSellerTaxOfficeAndRegistry, fixed: true, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Ruhsatname No</span><span class="colon">:</span>${dottedValue(settings.kdv4aSellerLicenseNumber, fixed: true, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Satışa Ait faturanın Tarih ve No' su</span><span class="colon">:</span>${dottedValue(record.invoiceNumber?.trim().isNotEmpty == true ? '$applicationDate / ${record.invoiceNumber!.trim()}' : applicationDate, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Cihazın Garanti Süresi</span><span class="colon">:</span>${dottedValue(settings.kdv4aWarrantyPeriod, fixed: true, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Firmanın Kaşesi ve Yetkilinin İmzası</span><span class="colon">:</span>${dottedValue('', fallback: '', extraClass: 'grow')}</div>

<div class="line"><span class="label" style="font-weight:700;">2- CİHAZI SATIN ALAN KİŞİ VEYA İŞLETMENİN</span></div>
<div class="line indent-1"><span class="label">-- Adı - Soyadı / Ünvanı</span><span class="colon">:</span>${dottedValue(businessName, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- İşyeri Adresi</span><span class="colon">:</span>${dottedValue(workAddress, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No</span><span class="colon">:</span>${dottedValue(buyerTaxRegistry.trim(), extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Cihazın çalıştırılma Tarihi</span><span class="colon">:</span>${dottedValue(okcDate, extraClass: 'grow')}</div>

<div class="line"><span class="label" style="font-weight:700;">3- SATIŞI YAPILAN CİHAZIN ÖZELLİKLERİ</span></div>
<div class="line indent-1"><span class="label">-- Markası ve Modeli</span><span class="colon">:</span>${dottedValue(([if (brand?.trim().isNotEmpty ?? false) brand!.trim(), if (model?.trim().isNotEmpty ?? false) model!.trim()].join(' / ')), extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Cihaz Sicil No</span><span class="colon">:</span>${dottedValue(stockRegistry, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Mali Sembol ve Firma Kodu</span><span class="colon">:</span>${dottedValue(fiscalSymbol, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- Cihazın Departman Sayısı</span><span class="colon">:</span>${dottedValue(settings.kdv4aDepartmentCount, fixed: true, extraClass: 'grow')}</div>

<div class="line"><span class="label" style="font-weight:700;">4- YETKİLİ BAKIM ONARIM SERVİSİNİN</span></div>
<div class="line indent-1"><span class="label">-- Adı - Soyadı / Ünvanı</span><span class="colon">:</span>${dottedValue(settings.kdv4aServiceCompanyName, fixed: true, extraClass: 'grow')}</div>
<div class="line indent-1"><span class="label">-- İşyeri Adresi</span><span class="colon">:</span>${dottedValue(settings.kdv4aServiceCompanyAddress, fixed: true, extraClass: 'grow')}</div>

<div class="line"><span class="label" style="font-weight:700;">5- CİHAZA MALİ MÜHÜRÜ TATBİK EDENİN</span></div>
<div class="line indent-1">
  <span class="label">İmzası</span>
  ${dottedValue('', fallback: '', extraClass: 'short')}
  <span class="label">Açık İsmi</span><span class="colon">:</span>
  ${dottedValue(settings.kdv4aSealApplicantName, fixed: true, extraClass: 'short')}
  <span class="label">Makamı</span><span class="colon">:</span>
  ${dottedValue(settings.kdv4aSealApplicantTitle, fixed: true, extraClass: 'short')}
</div>

<div class="box">
  <div class="box-title">ÖDEME KAYDEDİCİ CİHAZ KULLANIMINA AİT</div>
  <div class="mini-line">
    <span class="label">Onay Belgesi Tarihi</span><span class="colon">:</span>
    ${dottedValue(settings.kdv4aApprovalDocumentDate, fixed: true, extraClass: 'short')}
    <span class="label">Sayısı</span><span class="colon">:</span>
    ${dottedValue(settings.kdv4aApprovalDocumentNumber, fixed: true, extraClass: 'short')}
  </div>
</div>

<p class="notice">
  Mali mühürü bozulmamış olarak Ödeme Kaydedici Cihazın, Ödeme Kaydedici Cihaz Kullanımına ait
  Onay Belgesi (Forma. KDV 5) ile birlikte alıcıya teslim edildiği ve teslim alındığı beyan olunur.
</p>

<div class="dual-sign">
  <div class="dual-col">
    <div class="head">TESLİM EDENİN</div>
    <div class="mini-line"><span class="label">İmzası</span><span class="colon">:</span>${dottedValue('', fallback: '', extraClass: 'short')}</div>
    <div class="mini-line"><span class="label">Açık İsmi</span><span class="colon">:</span>${dottedValue('', fallback: '', extraClass: 'short')}</div>
    <div class="mini-line"><span class="label">Makamı</span><span class="colon">:</span>${dottedValue('', fallback: '', extraClass: 'short')}</div>
    <div class="mini-line" style="margin-top:26px;"><span class="label">Tarih</span><span class="colon">:</span>${dottedValue('', fallback: '', extraClass: 'short')}</div>
  </div>
  <div class="dual-col">
    <div class="head"><span class="underline-title">TESLİM ALANIN /<br>YETKİLİ SATICININ</span></div>
    <div class="mini-line"><span class="label">İmzası</span><span class="colon">:</span>${dottedValue('', fallback: '', extraClass: 'short')}</div>
    <div class="mini-line"><span class="label">Açık İsmi</span><span class="colon">:</span>${dottedValue(settings.kdv4aDeliveryReceiverName, fixed: true, extraClass: 'short')}</div>
    <div class="mini-line"><span class="label">Makamı</span><span class="colon">:</span>${dottedValue(settings.kdv4aDeliveryReceiverTitle, fixed: true, extraClass: 'short')}</div>
    <div class="mini-line indent-1">(${dottedValue('Firma Kaşesi', fixed: true, extraClass: 'short')})</div>
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
