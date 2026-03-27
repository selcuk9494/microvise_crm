// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'scrap_form_model.dart';

Future<bool> printScrapForm(
  ScrapFormRecord record, {
  ScrapFormPrintSettings? settings,
}) async {
  final htmlContent = _buildPrintableHtml(
    record,
    settings: settings ?? ScrapFormPrintSettings.defaults,
  );
  final popup = html.window.open('', '_blank');
  if (popup is! html.Window) return false;
  popup.document.documentElement?.setInnerHtml(
    htmlContent,
    treeSanitizer: html.NodeTreeSanitizer.trusted,
  );
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

  String blueValue(String? value, {String fallback = ''}) {
    final text = (value ?? '').trim();
    return '<span class="blue-value">${escape(text.isEmpty ? fallback : text)}</span>';
  }

  String redValue(String value) {
    return '<span class="red-value">${escape(value)}</span>';
  }

  String dottedLine(String valueHtml, {String extraClass = ''}) {
    final klass = extraClass.isEmpty ? 'line-fill' : 'line-fill $extraClass';
    return '<span class="$klass">$valueHtml</span>';
  }

  final dateText = formatDate(record.formDate);
  final startDateText = formatDate(record.okcStartDate);
  final lastUsedDateText = formatDate(record.lastUsedDate);

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
        margin: 7mm;
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
        width: 780px;
        margin: 0 auto;
        padding: 4px 2px 10px;
      }
      .top-code {
        text-align: right;
        color: #ff0000;
        font-size: 18px;
        font-weight: 700;
        margin-bottom: 4px;
      }
      .title {
        color: #ff0000;
        text-align: center;
        font-size: 26px;
        font-weight: 700;
        line-height: 1.3;
        white-space: pre-line;
        margin: 0 0 8px;
      }
      .top-meta {
        width: 300px;
        margin-left: auto;
        margin-bottom: 20px;
      }
      .meta-row {
        display: flex;
        align-items: baseline;
        gap: 10px;
        margin: 3px 0;
      }
      .meta-label {
        width: 110px;
        color: #ff0000;
        font-size: 22px;
        font-weight: 700;
        text-align: right;
      }
      .line-fill {
        flex: 1;
        border-bottom: 2px dotted #333;
        min-height: 28px;
        display: inline-flex;
        align-items: center;
        padding-left: 8px;
      }
      .red-heading {
        color: #ff0000;
        font-size: 19px;
        font-weight: 700;
      }
      .yellow-heading {
        color: #000;
        background: #fff200;
        font-size: 18px;
        font-weight: 700;
        display: inline-block;
        padding: 1px 4px;
      }
      .red-line {
        display: flex;
        align-items: baseline;
        gap: 10px;
        margin: 2px 0;
      }
      .red-label {
        width: 340px;
        color: #ff0000;
        font-size: 17px;
        font-weight: 700;
      }
      .yellow-label {
        width: 380px;
        color: #000;
        background: #fff200;
        font-size: 17px;
        font-weight: 700;
        padding: 1px 4px;
      }
      .sub-label {
        width: 440px;
        color: #000;
        background: #fff200;
        font-size: 16px;
        font-weight: 700;
        padding: 1px 4px;
        margin-left: 26px;
      }
      .colon {
        color: #ff0000;
        font-size: 18px;
        font-weight: 700;
      }
      .value-colon {
        color: #000;
        font-size: 17px;
        font-weight: 700;
        padding: 0 4px;
      }
      .blue-value {
        color: #006cc6;
        font-size: 17px;
        font-weight: 700;
      }
      .red-value {
        color: #ff0000;
        font-size: 17px;
        font-weight: 700;
      }
      .section-gap {
        height: 10px;
      }
      .spacer-lines {
        margin-top: 8px;
      }
      .spacer-line {
        border-bottom: 2px dotted #333;
        height: 24px;
        margin-bottom: 6px;
      }
      .signature-row {
        display: flex;
        justify-content: space-between;
        margin-top: 74px;
      }
      .signature-box {
        width: 300px;
        text-align: center;
      }
      .signature-title {
        color: #ff0000;
        font-size: 18px;
        font-weight: 700;
        white-space: pre-line;
        margin-bottom: 56px;
      }
      .section-line {
        display: flex;
        align-items: baseline;
        gap: 10px;
        margin: 2px 0;
      }
      .section-value {
        flex: 1;
        border-bottom: 2px dotted #333;
        min-height: 28px;
        display: inline-flex;
        align-items: center;
        padding-left: 8px;
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
          ${dottedLine(blueValue(dateText))}
        </div>
        <div class="meta-row">
          <div class="meta-label">${escape(settings.rowNumberLabel)} :</div>
          ${dottedLine(blueValue(record.rowNumber))}
        </div>
      </div>

      <div class="red-heading">${escape(settings.serviceSectionTitle)}</div>
      <div class="red-line">
        <div class="red-label">${escape(settings.serviceCompanyLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(redValue(settings.serviceCompanyValue))}
      </div>
      <div class="red-line">
        <div class="red-label">${escape(settings.serviceIdentityLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(redValue(settings.serviceIdentityValue))}
      </div>
      <div class="red-line">
        <div class="red-label">${escape(settings.serviceAddressLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(redValue(settings.serviceAddressValue))}
      </div>
      <div class="red-line">
        <div class="red-label">${escape(settings.serviceTaxLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(redValue(settings.serviceTaxValue))}
      </div>

      <div class="section-gap"></div>
      <div class="red-heading">${escape(settings.ownerSectionTitle)} :</div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.ownerNameLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.customerName))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.ownerAddressLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.customerAddress))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.ownerTaxLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.customerTaxOfficeAndNumber))}
      </div>

      <div class="section-line">
        <div class="yellow-label">${escape(settings.deviceSectionTitle)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.deviceBrandModelRegistry))}
      </div>
      <div class="section-line">
        <div class="yellow-label">${escape(settings.startDateLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(startDateText))}
      </div>
      <div class="section-line">
        <div class="yellow-label">${escape(settings.lastUsedDateLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(lastUsedDateText))}
      </div>

      <div class="section-line">
        <div class="yellow-label">${escape(settings.summaryTitle)}</div>
        <div class="value-colon">:</div>
        ${dottedLine('')}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.zReportLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.zReportCount))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.vatTotalLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.totalVatCollection))}
      </div>
      <div class="section-line">
        <div class="sub-label">${escape(settings.grossTotalLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.totalCollection))}
      </div>

      <div class="section-line">
        <div class="yellow-label">${escape(settings.purposeLabel)}</div>
        <div class="value-colon">:</div>
        ${dottedLine(blueValue(record.interventionPurpose))}
      </div>

      <div class="spacer-lines">
        <div class="spacer-line"></div>
        <div class="spacer-line"></div>
      </div>

      <div class="red-line">
        <div class="red-label">${escape(settings.otherFindingsLabel)}</div>
        <div class="colon">:</div>
        ${dottedLine(blueValue(record.otherFindings))}
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
