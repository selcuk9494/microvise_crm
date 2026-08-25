# WordPress fatura ödeme

## Acil: “Gecersiz callback” düzeltmesi

1. `microvise-invoice-bridge.php` dosyasını canlı siteye yükle:
   `wp-content/plugins/microvise-invoice-bridge/microvise-invoice-bridge.php`
2. WP Admin → Eklentiler → **Microvise Invoice Payment Bridge** → Etkinleştir

Bu, banka dönüşündeki `callback=invoice_hosted` isteğini CRM’e iletir.

## Kalıcı sayfa (opsiyonel)

- `page-invoice-payment.php` → tema klasörüne
- Sonra Vercel: `INVOICE_PAYMENT_HOSTED_PAGE_URL=https://www.microvise.net/fatura-odeme`
- Bridge plugin aktifken: `INVOICE_PAYMENT_USE_WP_BRIDGE=1`

## CRM (şimdilik)

Deploy sonrası banka dönüşü doğrudan  
`https://crm.microvise.net/api/invoice-pay?action=callback&token=...`  
adresine gider (WP bridge gerekmez). **Yeni ödeme linki** üret.
