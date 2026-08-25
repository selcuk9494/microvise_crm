# WordPress fatura ödeme — v1.3.0

## Kurulum

1. `microvise-invoice-bridge.php` →  
   `wp-content/plugins/microvise-invoice-bridge/microvise-invoice-bridge.php`
2. Sürüm **1.3.0** olsun (kapat-aç)
3. CRM Vercel deploy’unun tamamlanmasını bekleyin

## Özellikler

- NestPay ödeme (TRY dönüşümü + CC5)
- **Sanal POS iade**: CRM ··· menü → “Sanal POS iade”  
  Bankaya Void/Credit + CRM tahsilatını geri alır

İade için WooCommerce Halkbank `store_key` CRM env ile aynı olmalı  
(`INVOICE_PAYMENT_STORE_KEY` / `LICENSE_PAYMENT_STORE_KEY`).
