// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import '../../core/format/currency_format.dart';
import 'scrap_form_model.dart';

Future<bool> printScrapForm(
  ScrapFormRecord record, {
  ScrapFormPrintSettings? settings,
}) async {
  final htmlContent = _buildPrintableHtml(
    record,
    settings: settings ?? ScrapFormPrintSettings.defaults,
  );
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.window.open(url, '_blank');
  } catch (_) {
    try {
      html.window.location.assign(url);
    } catch (_) {
      html.window.location.href = url;
    }
  }
  Future<void>.delayed(const Duration(seconds: 5), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}

String _buildPrintableHtml(
  ScrapFormRecord record, {
  required ScrapFormPrintSettings settings,
}) {
  String escape(String? value) {
    return (html.DivElement()..text = (value ?? '').trim()).innerHtml ?? '';
  }

  String formatDate(DateTime? value) {
    if (value == null) return '';
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  String valueText(String? value, {String fallback = ''}) {
    final text = (value ?? '').trim();
    return '<span class="value-text">${escape(text.isEmpty ? fallback : text)}</span>';
  }

  String constantText(String value) {
    return '<span class="constant-text">${escape(value)}</span>';
  }

  String dottedLine(String valueHtml, {String extraClass = ''}) {
    final klass = extraClass.isEmpty ? 'line-fill' : 'line-fill $extraClass';
    return '<span class="$klass">$valueHtml</span>';
  }

  final dateText = formatDate(record.formDate);
  final startDateText = formatDate(record.okcStartDate);
  final lastUsedDateText = formatDate(record.lastUsedDate);
  final totalVatText = formatCurrencyDisplay(record.totalVatCollection);
  final totalCollectionText = formatCurrencyDisplay(record.totalCollection);

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
        width: 720px;
        margin: 0 auto;
        padding: 2px 0 6px;
      }
      .top-code {
        text-align: right;
        color: #000;
        font-size: 15px;
        font-weight: 700;
        margin-bottom: 2px;
      }
      .title {
        color: #000;
        text-align: center;
        font-size: 22px;
        font-weight: 700;
        line-height: 1.15;
        white-space: pre-line;
        margin: 0 0 4px;
      }
      .top-meta {
        width: 260px;
        margin-left: auto;
        margin-bottom: 10px;
      }
      .meta-row {
        display: flex;
        align-items: baseline;
        gap: 8px;
        margin: 1px 0;
      }
      .meta-label {
        width: 92px;
        color: #000;
        font-size: 18px;
        font-weight: 700;
        text-align: right;
      }
      .line-fill {
        flex: 1;
        border-bottom: 2px dotted #333;
        min-height: 22px;
        display: inline-flex;
        align-items: center;
        padding-left: 4px;
      }
      .section-heading {
        color: #000;
        font-size: 16px;
        font-weight: 700;
      }
      .section-subheading {
        color: #000;
        background: transparent;
        font-size: 15px;
        font-weight: 700;
        display: inline-block;
        padding: 0 2px;
      }
      .section-row {
        display: flex;
        align-items: baseline;
        gap: 8px;
        margin: 1px 0;
      }
      .section-label {
        width: 300px;
        color: #000;
        font-size: 15px;
        font-weight: 700;
      }
      .field-label {
        width: 340px;
        color: #000;
        background: transparent;
        font-size: 15px;
        font-weight: 700;
        padding: 0 2px;
      }
      .sub-label {
        width: 390px;
        color: #000;
        background: transparent;
        font-size: 14px;
        font-weight: 700;
        padding: 0 2px;
        margin-left: 18px;
      }
      .colon {
        color: #000;
        font-size: 15px;
        font-weight: 700;
      }
      .value-colon {
        color: #000;
        font-size: 15px;
        font-weight: 700;
        padding: 0 2px;
      }
      .value-text {
        color: #000;
        font-size: 15px;
        font-weight: 700;
      }
      .constant-text {
        color: #000;
        font-size: 15px;
        font-weight: 700;
      }
      .section-gap {
        height: 6px;
      }
      .spacer-lines {
        margin-top: 4px;
      }
      .spacer-line {
        border-bottom: 2px dotted #333;
        height: 18px;
        margin-bottom: 4px;
      }
      .signature-row {
        display: flex;
        justify-content: space-between;
        margin-top: 36px;
      }
      .signature-box {
        width: 260px;
        text-align: center;
      }
      .signature-title {
        color: #000;
        font-size: 15px;
        font-weight: 700;
        white-space: pre-line;
        margin-bottom: 28px;
      }
      .section-line {
        display: flex;
        align-items: baseline;
        gap: 8px;
        margin: 1px 0;
      }
      .section-value {
        flex: 1;
        border-bottom: 2px dotted #333;
        min-height: 22px;
        display: inline-flex;
        align-items: center;
        padding-left: 4px;
      }
    </style>
  </head>
  <body>
    <div class="sheet">
      <div class="top-code">${escape(settings.formCode)}</div>
      <div class="title">${escape(settings.title)}</div>

      <div class="top-meta">
        <div class="meta-row">
          <div class="meta-label">${escape(settings.dateLabel)} :</div>
          ${dottedLine(valueText(dateText))}
        </div>
        <div class="meta-row">
          <div class="meta-label">${escape(settings.rowNumberLabel)} :</div>
          ${dottedLine(valueText(record.rowNumber))}
        </div>
      </div>

      <div class="section-heading">${escape(settings.serviceSectionTitle)}</div>
      <div class="section-row">
        <div class="section-label">${escape(settings.serviceCompanyLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(constantText(settings.serviceCompanyValue))}
      </div>
      <div class="section-row">
        <div class="section-label">${escape(settings.serviceIdentityLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(constantText(settings.serviceIdentityValue))}
      </div>
      <div class="section-row">
        <div class="section-label">${escape(settings.serviceAddressLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(constantText(settings.serviceAddressValue))}
      </div>
      <div class="section-row">
        <div class="section-label">${escape(settings.serviceTaxLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(constantText(settings.serviceTaxValue))}
      </div>

      <div class="section-gap"></div>
      <div class="section-heading">${escape(settings.ownerSectionTitle)} :</div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.ownerNameLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(record.customerName))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.ownerAddressLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(record.customerAddress))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.ownerTaxLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(record.customerTaxOfficeAndNumber))}
      </div>

      <div class="section-line">
        <div class="field-label">${escape(settings.deviceSectionTitle)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(record.deviceBrandModelRegistry))}
      </div>
      <div class="section-line">
        <div class="field-label">${escape(settings.startDateLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(startDateText))}
      </div>
      <div class="section-line">
        <div class="field-label">${escape(settings.lastUsedDateLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(lastUsedDateText))}
      </div>

      <div class="section-line">
        <div class="field-label">${escape(settings.summaryTitle)}</div>
        <div class="value-colon">:</div>
        ${dottedLine('')}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.zReportLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(record.zReportCount))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.vatTotalLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(totalVatText))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.grossTotalLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(totalCollectionText))}
      </div>

      <div class="section-line">
        <div class="field-label">${escape(settings.purposeLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(valueText(record.interventionPurpose))}
      </div>

      <div class="spacer-lines">
        <div class="spacer-line"></div>
        <div class="spacer-line"></div>
      </div>

      <div class="section-row">
        <div class="section-label">${escape(settings.otherFindingsLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(valueText(record.otherFindings))}
      </div>
      <div class="spacer-lines">
        <div class="spacer-line"></div>
        <div class="spacer-line"></div>
      </div>

      <div class="signature-row">
        <div class="signature-box">
          <div class="signature-title">${escape(settings.ownerSignatureTitle)}</div>
        </div>
        <div class="signature-box">
          <div class="signature-title">${escape(settings.serviceSignatureTitle)}</div>
        </div>
      </div>
    </div>
  </body>
</html>
''';
}
