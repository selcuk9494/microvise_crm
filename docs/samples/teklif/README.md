# Teklif PDF Örnekleri

Stok görselleri **42×42 px** küçük resim kutusuna `contain` ile sığacak şekilde tasarlanmıştır.

## Örnek dosyalar

| Dosya | Para birimi | Not |
|-------|-------------|-----|
| `teklif_try_ornek.pdf` | TL | KDV hariç giriş |
| `teklif_try_kdv_dahil_ornek.pdf` | TL | Formda KDV dahil; tabloda matrah |
| `teklif_usd_ornek.pdf` | USD | KDV %0 |
| `teklif_eur_ornek.pdf` | EUR | 3 kalem (1 görselsiz) |
| `teklif_gbp_ornek.pdf` | GBP | Mt birimli kalem |

Örnek küçük resim kaynakları: `thumbs/` klasörü.

## Yeniden oluşturma

```bash
flutter test test/quote_pdf_samples_test.dart
```

## Şablon — ürün satırı

```
┌────────┐  Network Switch 24 Port
│ 42x42  │  Cisco CBS350-24T-4G
│ thumb  │
└────────┘
```

- Görsel yoksa gri çerçeveli `—` placeholder
- Görsel varsa beyaz kutu içinde tam sığdırma (`BoxFit.contain`)
- Ürün adı sağda, çok satırlı olabilir
- KDV dahil tekliflerde üstte “Fiyat girişi: KDV dahil” ve `*` notu görünür
