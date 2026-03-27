// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

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

  String blue(String? value) =>
      '<span class="blue">${escape((value ?? '').trim())}</span>';

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
      @page { size: A4 portrait; margin: 7mm; }
      body {
        margin: 0;
        background: #fff;
        color: #000;
        font-family: Arial, Helvetica, sans-serif;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }
      .sheet { width: 780px; margin: 0 auto; padding: 2px; }
      .title {
        color: #ff0000;
        text-align: center;
        font-size: 24px;
        font-weight: 700;
        line-height: 1.2;
        white-space: pre-line;
      }
      .subtitle {
        color: #ff0000;
        text-align: center;
        font-size: 18px;
        font-weight: 700;
        margin-top: 4px;
      }
      .top-row {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        margin-top: 12px;
      }
      .office {
        color: #ff0000;
        font-size: 17px;
        font-weight: 700;
        line-height: 1.3;
        white-space: pre-line;
      }
      .row-no {
        display: flex;
        align-items: baseline;
        gap: 8px;
        color: #ff0000;
        font-size: 17px;
        font-weight: 700;
      }
      .dotted {
        display: inline-flex;
        align-items: center;
        min-height: 24px;
        border-bottom: 2px dotted #333;
        flex: 1;
        padding-left: 4px;
      }
      .section {
        margin-top: 10px;
      }
      .section-title {
        color: #ff0000;
        font-size: 17px;
        font-weight: 700;
      }
      .line {
        display: flex;
        align-items: baseline;
        gap: 8px;
        margin: 2px 0;
      }
      .label {
        background: #fff200;
        font-size: 16px;
        font-weight: 700;
        padding: 1px 4px;
        color: #000;
      }
      .plain-label {
        font-size: 16px;
        font-weight: 700;
        color: #000;
        padding: 1px 4px;
      }
      .blue {
        color: #000;
        font-size: 16px;
        font-weight: 700;
      }
      .red {
        color: #ff0000;
        font-size: 16px;
        font-weight: 700;
      }
      .value-colon {
        color: #000;
        font-weight: 700;
      }
      .signature-row {
        display: flex;
        justify-content: space-between;
        gap: 40px;
        margin-top: 18px;
      }
      .signature-col {
        flex: 1;
      }
      .sig-title {
        color: #ff0000;
        font-size: 17px;
        font-weight: 700;
        margin-bottom: 6px;
      }
      .office-fill {
        margin-top: 10px;
        border-top: 2px solid #333;
        border-bottom: 2px solid #333;
        text-align: center;
        color: #ff0000;
        font-size: 17px;
        font-weight: 700;
        padding: 2px 0;
      }
      .office-text {
        margin-top: 8px;
        color: #ff0000;
        font-size: 16px;
        font-weight: 700;
      }
      .controller {
        margin-top: 18px;
        text-align: center;
        color: #ff0000;
        font-size: 16px;
        font-weight: 700;
      }
      .controller-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 18px 48px;
        margin-top: 6px;
      }
      .small-line {
        display: flex;
        align-items: baseline;
        gap: 8px;
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
          ${dotted(blue(record.rowNumber), extra: 'row')}
        </div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.transferorSectionTitle)}</div>
        <div class="line"><span class="label">${escape(settings.transferorNameLabel)} :</span>${dotted(blue(record.transferorName))}</div>
        <div class="line"><span class="label">${escape(settings.transferorAddressLabel)} :</span>${dotted(blue(record.transferorAddress))}</div>
        <div class="line"><span class="label">${escape(settings.transferorTaxLabel)} :</span>${dotted(blue(record.transferorTaxOfficeAndRegistry))}</div>
        <div class="line"><span class="label">${escape(settings.transferorApprovalLabel)} :</span>${dotted(blue(record.transferorApprovalDateNo))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.transfereeSectionTitle)}</div>
        <div class="line"><span class="label">${escape(settings.transfereeNameLabel)} :</span>${dotted(blue(record.transfereeName))}</div>
        <div class="line"><span class="label">${escape(settings.transfereeAddressLabel)} :</span>${dotted(blue(record.transfereeAddress))}</div>
        <div class="line"><span class="label">${escape(settings.transfereeTaxLabel)} :</span>${dotted(blue(record.transfereeTaxOfficeAndRegistry))}</div>
        <div class="line"><span class="label">${escape(settings.transfereeApprovalLabel)} :</span>${dotted(blue(record.transfereeApprovalDateNo))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.deviceSummaryTitle)}</div>
        <div class="line"><span class="label">${escape(settings.totalSalesReceiptLabel)} :</span>${dotted(blue(record.totalSalesReceipt))}</div>
        <div class="line"><span class="label">${escape(settings.vatCollectedLabel)} :</span>${dotted(blue(record.vatCollected))}</div>
        <div class="line"><span class="label">${escape(settings.lastReceiptDateNoLabel)} :</span>${dotted(blue(record.lastReceiptDateNo))}</div>
        <div class="line"><span class="label">${escape(settings.zReportCountLabel)} :</span>${dotted(blue(record.zReportCount))}</div>
        <div class="line"><span class="label">${escape(settings.otherDeviceInfoLabel)} :</span>${dotted(blue(record.otherDeviceInfo))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.deviceInfoTitle)}</div>
        <div class="line"><span class="label">${escape(settings.brandModelLabel)} :</span>${dotted(blue(record.brandModel))}</div>
        <div class="line"><span class="label">${escape(settings.deviceSerialNoLabel)} :</span>${dotted(blue(record.deviceSerialNo))}</div>
        <div class="line"><span class="label">${escape(settings.fiscalSymbolCompanyCodeLabel)} :</span>${dotted(blue(record.fiscalSymbolCompanyCode))}</div>
        <div class="line"><span class="label">${escape(settings.departmentCountLabel)} :</span>${dotted(blue(record.departmentCount))}</div>
      </div>

      <div class="section">
        <div class="section-title">${escape(settings.transferInfoTitle)}</div>
        <div class="line"><span class="label">${escape(settings.transferDateLabel)} :</span>${dotted(blue(formatDate(record.transferDate)))}</div>
        <div class="line"><span class="label">${escape(settings.transferReasonLabel)} :</span>${dotted(blue(record.transferReason))}</div>
        <div class="line"><span class="red">${escape(settings.serviceCompanyLabel)} :</span>${dotted('<span class="red">${escape(settings.serviceCompanyValue)}</span>')}</div>
      </div>

      <div style="text-align:center; margin-top:8px;" class="red">${escape(settings.statementText)}</div>

      <div class="signature-row">
        <div class="signature-col">
          <div class="sig-title">${escape(settings.transferorSignatureTitle)}</div>
          <div class="small-line"><span class="red">İmzası</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="red">Açık İsmi</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="red">Adresi.</span><span class="value-colon">:</span>${dotted('')}</div>
        </div>
        <div class="signature-col">
          <div class="sig-title">${escape(settings.transfereeSignatureTitle)}</div>
          <div class="small-line"><span class="red">İmzası</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="red">Açık İsmi</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="red">Adresi</span><span class="value-colon">:</span>${dotted('')}</div>
        </div>
      </div>

      <div class="office-fill">${escape(settings.officeFillTitle)}</div>
      <div class="office-text">${escape(settings.officeFillText)}</div>

      <div class="controller">${escape(settings.controllerTitle)}</div>
      <div class="controller-grid">
        <div>
          <div class="small-line"><span class="red">İmzası</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="red">Açık İsmi</span><span class="value-colon">:</span>${dotted('')}</div>
          <div class="small-line"><span class="red">Görevi</span><span class="value-colon">:</span>${dotted('')}</div>
        </div>
        <div>
          <div class="small-line"><span class="red"> </span><span class="value-colon"></span>${dotted('')}</div>
          <div class="small-line"><span class="red"> </span><span class="value-colon"></span>${dotted('')}</div>
          <div class="small-line"><span class="red"> </span><span class="value-colon"></span>${dotted('')}</div>
        </div>
      </div>
      <div style="width:300px; margin-top:8px;">
        <div class="small-line"><span class="red">${escape(settings.controllerDateLabel)} :</span>${dotted('')}</div>
      </div>
    </div>
  </body>
</html>
''';
}
