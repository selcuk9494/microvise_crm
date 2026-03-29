// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import '../../core/format/currency_format.dart';
import 'transfer_form_model.dart';

Future<bool> printTransferForm(
  TransferFormRecord record, {
  TransferFormPrintSettings? settings,
}) async {
  final htmlContent = _buildPrintableHtml(
    record,
    settings: settings ?? TransferFormPrintSettings.defaults,
  );
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future<void>.delayed(const Duration(seconds: 5), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}

String _buildPrintableHtml(
  TransferFormRecord record, {
  required TransferFormPrintSettings settings,
}) {
  String escape(String? value) {
    return (html.DivElement()..text = (value ?? '').trim()).innerHtml ?? '';
  }

  String formatDate(DateTime? value) {
    if (value == null) return '';
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  String dotted(String valueHtml, {String extra = ''}) {
    final klass = extra.isEmpty ? 'dotted' : 'dotted $extra';
    return '<span class="$klass">$valueHtml</span>';
  }

  String valueText(String? value) =>
      '<span class="value-text">${escape((value ?? '').trim())}</span>';

  final totalSalesText = formatCurrencyDisplay(record.totalSalesReceipt);
  final vatCollectedText = formatCurrencyDisplay(record.vatCollected);

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
      @page { size: A4 portrait; margin: 5mm; }
      body {
        margin: 0;
        background: #fff;
        color: #000;
        font-family: Arial, Helvetica, sans-serif;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }
      .sheet { width: 720px; margin: 0 auto; padding: 2px 0 6px; }
      .title {
        color: #000;
        text-align: center;
        font-size: 20px;
        font-weight: 700;
        line-height: 1.1;
        white-space: pre-line;
      }
      .subtitle {
        color: #000;
        text-align: center;
        font-size: 15px;
        font-weight: 700;
        margin-top: 2px;
      }
      .top-row {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        margin-top: 8px;
      }
      .office {
        color: #000;
        font-size: 15px;
        font-weight: 700;
        line-height: 1.15;
        white-space: pre-line;
      }
      .row-no {
        display: flex;
        align-items: baseline;
        gap: 6px;
        color: #000;
        font-size: 15px;
        font-weight: 700;
      }
      .dotted {
        display: inline-flex;
        align-items: center;
        min-height: 20px;
        border-bottom: 2px dotted #333;
        flex: 1;
        padding-left: 2px;
      }
      .section {
        margin-top: 6px;
      }
      .section-title {
        color: #000;
        font-size: 15px;
        font-weight: 700;
      }
      .line {
        display: flex;
        align-items: baseline;
        gap: 6px;
        margin: 1px 0;
      }
      .label {
        background: transparent;
        font-size: 14px;
        font-weight: 700;
        padding: 0 2px;
        color: #000;
      }
      .plain-label {
        font-size: 14px;
        font-weight: 700;
        color: #000;
        padding: 0 2px;
      }
      .value-text {
        color: #000;
        font-size: 14px;
        font-weight: 700;
      }
      .constant-text {
        color: #000;
        font-size: 14px;
        font-weight: 700;
      }
      .value-colon {
        color: #000;
        font-weight: 700;
      }
      .signature-row {
        display: flex;
        justify-content: space-between;
        gap: 28px;
        margin-top: 10px;
      }
      .signature-col {
        flex: 1;
      }
      .sig-title {
        color: #000;
        font-size: 15px;
        font-weight: 700;
        margin-bottom: 4px;
      }
      .office-fill {
        margin-top: 8px;
        border-top: 2px solid #333;
        border-bottom: 2px solid #333;
        text-align: center;
        color: #000;
        font-size: 15px;
        font-weight: 700;
        padding: 1px 0;
      }
      .office-text {
        margin-top: 6px;
        color: #000;
        font-size: 14px;
        font-weight: 700;
      }
      .controller {
        margin-top: 10px;
        text-align: center;
        color: #000;
        font-size: 14px;
        font-weight: 700;
      }
      .controller-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 10px 28px;
        margin-top: 4px;
      }
      .small-line {
        display: flex;
        align-items: baseline;
        gap: 6px;
      }
    </style>
  </head>
  <body>
    <div class="sheet">
      <div class="title">${escape(settings.title)}</div>
      <div class="subtitle">${escape(settings.subtitle)}</div>

      <div class="top-row">
        <div class="office">${escape(settings.officeTitle)}</div>
        <div class="row-no">
          <span>${escape(settings.rowNumberLabel)} :</span>
          ${dotted(valueText(record.rowNumber), extra: 'row')}
        </div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.transferorSectionTitle)}</div>
        <div class="line"><span class="label">${escape(settings.transferorNameLabel)} :</span>${dotted(valueText(record.transferorName))}</div>
        <div class="line"><span class="label">${escape(settings.transferorAddressLabel)} :</span>${dotted(valueText(record.transferorAddress))}</div>
        <div class="line"><span class="label">${escape(settings.transferorTaxLabel)} :</span>${dotted(valueText(record.transferorTaxOfficeAndRegistry))}</div>
        <div class="line"><span class="label">${escape(settings.transferorApprovalLabel)} :</span>${dotted(valueText(record.transferorApprovalDateNo))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.transfereeSectionTitle)}</div>
        <div class="line"><span class="label">${escape(settings.transfereeNameLabel)} :</span>${dotted(valueText(record.transfereeName))}</div>
        <div class="line"><span class="label">${escape(settings.transfereeAddressLabel)} :</span>${dotted(valueText(record.transfereeAddress))}</div>
        <div class="line"><span class="label">${escape(settings.transfereeTaxLabel)} :</span>${dotted(valueText(record.transfereeTaxOfficeAndRegistry))}</div>
        <div class="line"><span class="label">${escape(settings.transfereeApprovalLabel)} :</span>${dotted(valueText(record.transfereeApprovalDateNo))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.deviceSummaryTitle)}</div>
        <div class="line"><span class="label">${escape(settings.totalSalesReceiptLabel)} :</span>${dotted(valueText(totalSalesText))}</div>
        <div class="line"><span class="label">${escape(settings.vatCollectedLabel)} :</span>${dotted(valueText(vatCollectedText))}</div>
        <div class="line"><span class="label">${escape(settings.lastReceiptDateNoLabel)} :</span>${dotted(valueText(record.lastReceiptDateNo))}</div>
        <div class="line"><span class="label">${escape(settings.zReportCountLabel)} :</span>${dotted(valueText(record.zReportCount))}</div>
        <div class="line"><span class="label">${escape(settings.otherDeviceInfoLabel)} :</span>${dotted(valueText(record.otherDeviceInfo))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.deviceInfoTitle)}</div>
        <div class="line"><span class="label">${escape(settings.brandModelLabel)} :</span>${dotted(valueText(record.brandModel))}</div>
        <div class="line"><span class="label">${escape(settings.deviceSerialNoLabel)} :</span>${dotted(valueText(record.deviceSerialNo))}</div>
        <div class="line"><span class="label">${escape(settings.fiscalSymbolCompanyCodeLabel)} :</span>${dotted(valueText(record.fiscalSymbolCompanyCode))}</div>
        <div class="line"><span class="label">${escape(settings.departmentCountLabel)} :</span>${dotted(valueText(record.departmentCount))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.transferInfoTitle)}</div>
        <div class="line"><span class="label">${escape(settings.transferDateLabel)} :</span>${dotted(valueText(formatDate(record.transferDate)))}</div>
        <div class="line"><span class="label">${escape(settings.transferReasonLabel)} :</span>${dotted(valueText(record.transferReason))}</div>
        <div class="line"><span class="constant-text">${escape(settings.serviceCompanyLabel)} :</span>${dotted('<span class="constant-text">${escape(settings.serviceCompanyValue)}</span>')}</div>
      </div>

      <div style="text-align:center; margin-top:8px;" class="constant-text">${escape(settings.statementText)}</div>

      <div class="signature-row">
        <div class="signature-col">
          <div class="sig-title">${escape(settings.transferorSignatureTitle)}</div>
          <div class="small-line"><span class="constant-text">İmzası</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text">Açık İsmi</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text">Adresi.</span><span class="value-colon">:</span>${dotted('')}</div>
        </div>
        <div class="signature-col">
          <div class="sig-title">${escape(settings.transfereeSignatureTitle)}</div>
          <div class="small-line"><span class="constant-text">İmzası</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text">Açık İsmi</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text">Adresi</span><span class="value-colon">:</span>${dotted('')}</div>
        </div>
      </div>

      <div class="office-fill">${escape(settings.officeFillTitle)}</div>
      <div class="office-text">${escape(settings.officeFillText)}</div>

      <div class="controller">${escape(settings.controllerTitle)}</div>
      <div class="controller-grid">
        <div>
          <div class="small-line"><span class="constant-text">İmzası</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text">Açık İsmi</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text">Görevi</span><span class="value-colon">:</span>${dotted('')}</div>
        </div>
        <div>
          <div class="small-line"><span class="constant-text"> </span><span class="value-colon"></span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text"> </span><span class="value-colon"></span>${dotted('')}</div>
          <div class="small-line"><span class="constant-text"> </span><span class="value-colon"></span>${dotted('')}</div>
        </div>
      </div>
      <div style="width:300px; margin-top:8px;">
        <div class="small-line"><span class="constant-text">${escape(settings.controllerDateLabel)} :</span>${dotted('')}</div>
      </div>
    </div>
  </body>
</html>
''';
}
