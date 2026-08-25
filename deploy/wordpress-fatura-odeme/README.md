# WordPress fatura ödeme (ZORUNLU)

Aynı kart microvise.net mağazada çalışıp CRM’de “Güvenlik Kodu hatalı” veriyorsa
sorun kart değil: CRM NestPay imzası. Ödeme artık **WooCommerce Halkbank POS
ayarlarıyla** (çalışan yol) başlatılmalı.

## Kurulum (1 dosya)

1. Şu dosyayı canlı WordPress’e yükle:
   `microvise-invoice-bridge.php`
   → `wp-content/plugins/microvise-invoice-bridge/microvise-invoice-bridge.php`
2. WP Admin → Eklentiler → **Microvise Invoice Payment Bridge** → Etkinleştir
3. WooCommerce → Halkbank / Microvise POS ayarlarında merchant + store key dolu olsun
   (mağaza ödemesi zaten çalışıyorsa doludur)

## Ne yapar?

- `action=microvise_invoice_nestpay` → NestPay 3d formunu **WooCommerce’teki aynı
  PHP hash + store key** ile üretir
- `callback=invoice_hosted` → banka dönüşünü CRM’e iletir

CRM ödeme ekranı önce bu WP endpoint’ine gider; yoksa eski CRM yoluna düşer.
