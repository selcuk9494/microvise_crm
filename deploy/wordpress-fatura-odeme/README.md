# WordPress: Fatura Ödeme sayfası

Canlı siteye yükle (`wp-content/themes/microvise/`):

1. `page-invoice-payment.php` (yeni dosya)
2. `functions.php` — yerel `microvisesite` temasındaki güncel kopyayı yükle
   (veya sadece `invoice_hosted` bridge + `Fatura Odeme` sayfa oluşturma
   değişikliklerini mevcut canlı `functions.php` içine taşı)

Sonra bir kez siteyi aç: tema `fatura-odeme` sayfasını otomatik oluşturur.
Kontrol: https://www.microvise.net/fatura-odeme/

Bridge hedefi: `callback=invoice_hosted` → `https://crm.microvise.net/api/invoice-pay?action=callback&token=...`
