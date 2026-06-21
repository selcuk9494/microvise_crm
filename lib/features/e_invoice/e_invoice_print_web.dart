// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:intl/intl.dart';

import '../invoices/invoice_model.dart';

Future<bool> printEInvoice(Invoice invoice) async {
  final htmlContent = _buildInvoiceHtml(invoice);
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.window.open(url, '_blank');
  } catch (_) {
    html.window.location.href = url;
  }
  Future<void>.delayed(const Duration(seconds: 90), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}

String _buildInvoiceHtml(Invoice invoice) {
  final money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: invoice.currency == 'TRY' ? 'TL ' : '${invoice.currency} ',
    decimalDigits: 2,
  );
  final date = DateFormat('dd.MM.yyyy').format(invoice.invoiceDate);
  final rows = invoice.items.isEmpty
      ? '<tr><td colspan="6" class="muted">Fatura kalemi bulunamadı.</td></tr>'
      : invoice.items.map((item) {
          return '''
            <tr>
              <td>${_esc(item.description)}</td>
              <td class="num">${_fmt(item.quantity)}</td>
              <td>${_esc(item.unit)}</td>
              <td class="num">${money.format(item.unitPrice)}</td>
              <td class="num">%${_fmt(item.taxRate)}</td>
              <td class="num">${money.format(item.lineTotal)}</td>
            </tr>
          ''';
        }).join();

  return '''
<!doctype html>
<html lang="tr">
<head>
  <meta charset="utf-8">
  <title>${_esc(invoice.invoiceNumber)}</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: Arial, sans-serif; color: #0f172a; margin: 0; padding: 28px; }
    .top { display: flex; justify-content: space-between; gap: 24px; margin-bottom: 28px; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    .muted { color: #64748b; }
    .box { border: 1px solid #dbe4ef; border-radius: 8px; padding: 14px; }
    table { width: 100%; border-collapse: collapse; margin-top: 18px; }
    th { background: #eef4fb; text-align: left; color: #334155; }
    th, td { border-bottom: 1px solid #e2e8f0; padding: 10px; font-size: 13px; }
    .num { text-align: right; white-space: nowrap; }
    .summary { margin-left: auto; margin-top: 18px; width: 320px; }
    .line { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #e2e8f0; }
    .total { font-size: 18px; font-weight: 700; }
    @media print { body { padding: 16px; } button { display: none; } }
  </style>
</head>
<body>
  <button onclick="window.print()" style="float:right;padding:10px 14px;margin-bottom:14px">Yazdır / PDF</button>
  <div class="top">
    <div>
      <h1>${invoice.invoiceType == 'sales' ? 'Satış Faturası' : 'Alış Faturası'}</h1>
      <div class="muted">${_esc(invoice.invoiceNumber)}</div>
      <div class="muted">$date</div>
    </div>
    <div class="box" style="min-width:320px">
      <strong>Cari</strong><br>
      ${_esc(invoice.customerName ?? 'Cari')}<br>
      <span class="muted">Durum: ${_esc(_status(invoice.status))}</span>
    </div>
  </div>
  <table>
    <thead>
      <tr>
        <th>Ürün / Hizmet</th>
        <th class="num">Miktar</th>
        <th>Birim</th>
        <th class="num">Birim Fiyat</th>
        <th class="num">KDV</th>
        <th class="num">KDV Dahil</th>
      </tr>
    </thead>
    <tbody>$rows</tbody>
  </table>
  <div class="summary">
    <div class="line"><span>Ara Toplam</span><strong>${money.format(invoice.subtotal)}</strong></div>
    <div class="line"><span>İndirim</span><strong>${money.format(invoice.discountTotal)}</strong></div>
    <div class="line"><span>KDV</span><strong>${money.format(invoice.taxTotal)}</strong></div>
    <div class="line total"><span>Genel Toplam</span><span>${money.format(invoice.grandTotal)}</span></div>
  </div>
  <script>setTimeout(function(){ window.print(); }, 350);</script>
</body>
</html>
''';
}

String _esc(Object? value) {
  return (html.DivElement()..text = '${value ?? ''}').innerHtml ?? '';
}

String _fmt(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.0001) return rounded.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

String _status(String status) {
  return switch (status) {
    'draft' => 'Taslak',
    'paid' => 'Kapalı',
    'partial' => 'Kısmi Ödendi',
    'cancelled' => 'İptal',
    _ => 'Açık',
  };
}
