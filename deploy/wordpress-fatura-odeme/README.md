# WordPress fatura ödeme — v1.2.1

## Kurulum

1. `microvise-invoice-bridge-1.2.zip` veya `microvise-invoice-bridge.php` dosyasını yükle:
   `wp-content/plugins/microvise-invoice-bridge/microvise-invoice-bridge.php`
2. Eklentiler’de sürüm **1.2.1** olsun (gerekirse kapat-aç)
3. CRM’den **yeni ödeme linki** üret

## Ne yapar?

- CRM ödeme formu kartı **doğrudan** microvise.net WooCommerce POS’a POST eder (CORS/`Failed to fetch` yok)
- NestPay formu mağaza `receipt` ile aynı alanlar + USD→TRY
- Banka dönüşünde CC5 Auth, sonucu CRM’e bildirir

Ödeme sırasında “Bankaya yönlendiriliyorsunuz…” görünmeli.
