// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'fault_form_model.dart';

Future<bool> printFaultForm(FaultFormRecord record) async {
  final htmlContent = _buildPrintableHtml(record);
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future<void>.delayed(const Duration(seconds: 10), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}

String _buildPrintableHtml(FaultFormRecord record) {
  String escape(String? value) {
    return (html.DivElement()..text = (value ?? '').trim()).innerHtml ?? '';
  }

  String formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  String line(String label, String? value) {
    final text = (value ?? '').trim();
    return '''
<div class="line">
  <span class="label">${escape(label)}</span>
  <span class="colon">:</span>
  <span class="fill">${escape(text)}</span>
</div>
''';
  }

  final formDate = formatDate(record.formDate);
  final customerName = record.customerName;
  final address = (record.customerAddress ?? '').trim();
  final taxOffice = (record.customerTaxOffice ?? '').trim();
  final vkn = (record.customerVkn ?? '').trim();
  final brandModel = (record.deviceBrandModel ?? '').trim();
  final companyCode = (record.companyCodeAndRegistry ?? '').trim();
  final okcApproval = (record.okcApprovalDateAndNumber ?? '').trim();
  final faultDateTime = (record.faultDateTimeText ?? '').trim();
  final faultDesc = (record.faultDescription ?? '').trim();
  final lastZ = record.lastZReportDisplay.trim();
  final revenue = (record.totalRevenue ?? '').trim();
  final totalVat = (record.totalVat ?? '').trim();
  final revenueDisplay =
      revenue.isEmpty || revenue.contains('₺') ? revenue : '$revenue ₺';
  final vatDisplay =
      totalVat.isEmpty || totalVat.contains('₺') ? totalVat : '$totalVat ₺';

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
        margin: 6mm;
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
        width: 740px;
        margin: 0 auto;
      }
      .header {
        text-align: center;
        line-height: 1.15;
      }
      .kktc {
        font-size: 16px;
        font-weight: 700;
      }
      .ministry {
        font-size: 16px;
        font-weight: 700;
      }
      .dept {
        font-size: 14px;
        font-weight: 700;
        margin-top: 2px;
      }
      .city {
        font-size: 14px;
        font-weight: 800;
        margin-top: 2px;
      }
      .title {
        margin-top: 10px;
        font-size: 18px;
        font-weight: 800;
        letter-spacing: 0.3px;
      }
      .subtitle {
        font-size: 14px;
        font-weight: 700;
        margin-top: 2px;
      }
      .meta {
        margin-top: 10px;
        width: 260px;
        margin-left: auto;
        border: 2px solid #111827;
        border-radius: 8px;
        padding: 10px 12px;
      }
      .meta .row {
        display: flex;
        gap: 8px;
        align-items: baseline;
      }
      .meta .row .label {
        width: 90px;
        text-align: right;
        font-weight: 800;
      }
      .meta .row .value {
        flex: 1;
        border-bottom: 1px dotted #111827;
        padding-bottom: 2px;
      }
      .section {
        margin-top: 10px;
        border: 2px solid #111827;
        border-radius: 10px;
        padding: 12px 14px;
      }
      .servicebox {
        margin-top: 10px;
        border: 2px solid #111827;
        border-radius: 10px;
        padding: 12px 14px;
      }
      .section-title {
        font-weight: 800;
        font-size: 12px;
        margin-bottom: 6px;
      }
      .line {
        display: flex;
        align-items: baseline;
        gap: 6px;
        margin: 4px 0;
        font-size: 12px;
      }
      .label {
        width: 290px;
        font-weight: 700;
      }
      .colon {
        width: 10px;
        text-align: center;
        font-weight: 700;
      }
      .fill {
        flex: 1;
        border-bottom: 1px dotted #111827;
        min-height: 14px;
      }
      .bigfill {
        border: 2px solid #111827;
        border-radius: 10px;
        padding: 10px;
        min-height: 76px;
        white-space: pre-wrap;
        font-size: 12px;
      }
      .note {
        margin-top: 10px;
        font-size: 11px;
        line-height: 1.25;
      }
      .foot {
        margin-top: 10px;
        display: flex;
        justify-content: space-between;
        gap: 14px;
      }
      .seal {
        width: 240px;
        border: none;
        padding: 0;
      }
      .seal-title {
        font-weight: 800;
        font-size: 12px;
      }
      .datebox {
        width: 220px;
        border: none;
        padding: 0;
      }
      .datebox .row {
        display: flex;
        align-items: baseline;
        gap: 8px;
      }
      .datebox .row .label {
        width: 70px;
        font-weight: 800;
        color: #1D4ED8;
      }
      .datebox .row .value {
        flex: 1;
        border-bottom: 1px dotted #1D4ED8;
        color: #1D4ED8;
        font-weight: 800;
        padding-bottom: 2px;
      }
      .datebox .authority {
        margin-top: 12px;
        color: #0F172A;
        font-weight: 800;
        font-size: 12px;
        line-height: 1.25;
      }
    </style>
  </head>
  <body>
    <div class="sheet">
      <div class="header">
        <div class="kktc">K.K.T.C</div>
        <div class="ministry">MALİYE BAKANLIĞI</div>
        <div class="dept">Gelir ve Vergi Dairesi Müdürlüğüne</div>
        <div class="city">LEFKOŞA</div>
        <div class="title">ÖDEME KAYDEDİCİ CİHAZLARA AİT</div>
        <div class="title">ARIZA BİLDİRİM FORMU</div>
        <div class="subtitle">(Form. KDV 15A)</div>
      </div>

      <div class="servicebox">
        <div class="section-title">Ödeme Kaydedici Cihaz<br/>Satış ve Bakım - Onarım Ruhsatnamesi Sahibinin :</div>
        ${line('Adı Soyadı / Ünvanı', 'Microvise Innovation Ltd.')}
        ${line('Adresi', '')}
        ${line('Vergi Sicil No.', 'VKN:384003147')}
        ${line('Ruhsatname No', '19')}
      </div>

      <div class="meta">
        <div class="row">
          <div class="label">Tarih</div>
          <div class="value">${escape(formDate)}</div>
        </div>
      </div>

      <div class="section">
        <div class="section-title">TEKNİK MÜDAHALE TALEBİNDE BULUNAN YÜKÜMLÜNÜN :</div>
        ${line('Adı Soyadı / Ünvanı', customerName)}
        ${line('Adresi', address)}
        ${line('Bağlı Olduğu Vergi Dairesi', taxOffice)}
        ${line('Vergi Sicil No.', vkn)}
      </div>

      <div class="section">
        <div class="section-title">TEKNİK MÜDAHALEYE TABİ TUTULACAK CİHAZIN :</div>
        ${line('Marka ve Modeli', brandModel)}
        ${line('Firma Kodu ve Sicil No', companyCode)}
        ${line('Ödeme Kaydedici Cihaz Kullanım Onay Belgesi Tarih ve No', okcApproval)}
      </div>

      <div class="section">
        ${line('Arıza Tarih ve Saati', faultDateTime)}
        <div class="line" style="align-items:flex-start;">
          <span class="label">Arıza Tarifi</span>
          <span class="colon">:</span>
          <span class="fill" style="border:none;"></span>
        </div>
        <div class="bigfill">${escape(faultDesc)}</div>
        ${line("Alınan Son 'Z' Raporu Tarih ve No. 'su", lastZ)}
        ${line('Cihaza Kaydedilen Toplam Hasılat', revenueDisplay)}
        ${line('Cihaza Kaydedilen Toplam Kdv', vatDisplay)}
        ${line('Yetkili Bakım - Onarım Servisi', 'Microvise Innovation Ltd.')}
      </div>

      <div class="note">
        Yukarıda açıklaması verilen Ödeme Kaydedici Cihazın mali mühürünü sökülüp en geç 3 (üç) gün içerisinde gerekli tamir ve Bakım - Onarım işleminin yapılıp tekrar Gelir ve Vergi Dairesi Yetkili elemanlarına mühürletip yükümlüye teslim edilmesi gerekmektedir. Ayrıca yapılan tamir ve Bakım - Onarım işlemlerinin KDV 15 formu ile Gelir ve Vergi Dairesine bildirilmesi zorunludur.
      </div>

      <div class="foot">
        <div class="seal">
          <div class="seal-title">(Mühür)</div>
        </div>
        <div class="datebox">
          <div class="row">
            <div class="label">Tarih</div>
            <div class="value">${escape(formDate)}</div>
          </div>
          <div class="authority">
            <div>Gelir ve Vergi Dairesi</div>
            <div>Müdürü (A)</div>
          </div>
        </div>
      </div>
    </div>
  </body>
</html>
''';
}
