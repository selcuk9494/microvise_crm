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
        margin: 10mm 12mm;
      }
      * { box-sizing: border-box; }
      html, body {
        margin: 0;
        padding: 0;
        height: 100%;
        background: #fff;
        color: #000;
        font-family: Arial, Helvetica, "Segoe UI", sans-serif;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }
      .sheet {
        width: 186mm;
        height: 277mm;
        min-height: 277mm;
        margin: 0 auto;
        display: flex;
        flex-direction: column;
        justify-content: flex-start;
        padding-top: 2mm;
      }
      .blocks {
        flex: 0 0 auto;
        display: flex;
        flex-direction: column;
        gap: 5mm;
      }
      .block {
        flex: 0 0 auto;
      }
      .top-code {
        text-align: right;
        font-size: 13px;
        font-weight: 700;
        margin-bottom: 4px;
      }
      .title {
        text-align: center;
        font-size: 17px;
        font-weight: 800;
        letter-spacing: 0.2px;
        line-height: 1.25;
        white-space: pre-line;
        margin: 0 0 8px;
      }
      .top-meta {
        width: 70mm;
        margin-left: auto;
        margin-bottom: 2mm;
      }
      .meta-row,
      .section-row,
      .section-line {
        display: flex;
        align-items: baseline;
        gap: 6px;
        margin: 3px 0;
      }
      .meta-label {
        width: 22mm;
        font-size: 13px;
        font-weight: 800;
        text-align: right;
      }
      .section-heading {
        font-size: 13px;
        font-weight: 800;
        margin: 0 0 4px;
      }
      .section-label,
      .field-label {
        width: 78mm;
        font-size: 13px;
        font-weight: 700;
      }
      .sub-label {
        width: 72mm;
        margin-left: 6mm;
        font-size: 13px;
        font-weight: 700;
      }
      .colon,
      .value-colon {
        width: 3mm;
        text-align: center;
        font-size: 13px;
        font-weight: 700;
      }
      .line-fill {
        flex: 1;
        border-bottom: 1px dotted #111827;
        min-height: 5mm;
        display: inline-flex;
        align-items: flex-end;
        padding: 0 1mm 1mm;
      }
      .value-text,
      .constant-text {
        font-size: 13px;
        font-weight: 700;
      }
      .spacer-lines {
        margin-top: 2px;
      }
      .spacer-line {
        border-bottom: 1px dotted #111827;
        height: 5.5mm;
        margin-bottom: 1.5mm;
      }
      .signature-row {
        display: flex;
        justify-content: space-between;
        margin-top: auto;
        padding-top: 10mm;
        flex: 0 0 auto;
      }
      .signature-box {
        width: 70mm;
        text-align: center;
      }
      .signature-title {
        font-size: 13px;
        font-weight: 800;
        white-space: pre-line;
        margin-bottom: 16mm;
      }
      @media print {
        html, body {
          height: auto;
        }
        .sheet {
          width: 100%;
          height: 277mm;
          min-height: 277mm;
        }
      }
    </style>
  </head>
  <body>
    <div class="sheet">
      <div class="blocks">
        <div class="block">
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
        </div>

        <div class="block">
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
        </div>

        <div class="block">
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
        </div>

        <div class="block">
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
        </div>

        <div class="block">
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
        </div>

        <div class="block">
          <div class="section-line">
            <div class="field-label">${escape(settings.purposeLabel)}</div>
            <div class="value-colon">:</div>
            ${dottedLine(valueText(record.interventionPurpose))}
          </div>
          <div class="spacer-lines">
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
        </div>
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
