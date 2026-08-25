# WordPress fatura ödeme — v1.2 (zorunlu güncelleme)

Aynı kart mağazada çalışıp CRM’de “Güvenlik Kodu hatalı” veriyorsa:
Microvise POS **TRY** ile çalışıyor; mağaza USD’yi kura çeviriyor.
Ayrıca NestPay formu + 3D sonrası CC5 onayı WooCommerce kodundan gitmeli.

## Kurulum / güncelleme

1. `microvise-invoice-bridge.php` dosyasını **üzerine yaz**:
   `wp-content/plugins/microvise-invoice-bridge/microvise-invoice-bridge.php`
2. Eklentiler’de etkin olduğundan emin ol (gerekirse kapat-aç)
3. CRM’den **yeni ödeme linki** üret

## Bu sürüm ne yapar?

- NestPay formunu mağaza `receipt` ile **aynı alanlarla** üretir
- USD/EUR → Halkbank kuru ile **TRY (949)** çeker
- Banka dönüşünde WooCommerce’teki gibi **CC5 Auth** yapar
- Sonucu CRM’e bildirir (fatura kapanır)

## Kontrol

Ödeme sırasında “Bankaya yönlendiriliyorsunuz” ve (dövizde) “Karttan çekilecek: … TRY” görülmeli.
Hâlâ eski CRM hatası ise eklenti dosyası güncellenmemiştir.
