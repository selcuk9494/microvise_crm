# lib/design_system — Microvise Design System v2 (kod temeli)

Bu klasördeki dosyalar **katkı amaçlıdır (additive)**: hiçbiri bugün herhangi
bir ekran veya `lib/core/ui/*` bileşeni tarafından import edilmiyor. Amaç,
tasarım dokümanındaki (`docs/design-system/microvise-design-system-v2.md`)
kararları, ekran geçişleri başladığında hazır ve derlenebilir kod olarak
bulmaktır.

**Kural**: Bu klasördeki hiçbir dosya, ilgili ekranın yeniden tasarımı
onaylanmadan mevcut bir ekrana bağlanmaz. `core/ui/*` dosyaları da bu klasör
tamamlandı diye silinmez — bir ekran v2'ye taşındığında o ekranın kullandığı
eski bileşen (varsa ve başka ekran kullanmıyorsa) ayrı bir "temizlik" adımı
olarak kaldırılır.

## Dosyalar

| Dosya | Ne için | Konsolide ettiği eski implementasyonlar |
|---|---|---|
| `ds_tokens.dart` | Spacing/elevation/motion/breakpoint sabitleri | — (yeni katman, `AppTheme`'in renk token'larını değiştirmez) |
| `status_tone.dart` | Kanonik `DsStatusTone` + `DsStatusBadge` + `DsStatusDot` | `AppBadge` (tone mantığı), İş Emirleri `_compactStatusPill`/`_StatusPill`, Kanban inline status switch |
| `ds_kpi_tile.dart` | Kanonik `DsKpiTile` (sparkline/trend destekli) | Dashboard `_MetricTile`, Servis `_MetricCard`, `CompactStatCard` |

## Ekran geçişi kontrol listesi (her ekran için)

Bir ekran v2'ye taşınırken şu sıra izlenir:

1. Mevcut tasarımı eleştir (denetim raporundaki ilgili bölüm başlangıç noktasıdır).
2. En az 3 konsept öner, en iyisini seç.
3. Uygula — **yalnızca UI katmanı**; business logic/API/veri akışı değişmez.
4. Durum gösterimi varsa `DsStatusBadge`/`DsStatusDot` kullan, ekrana özel `_statusColor`/`_compactStatusPill` benzeri yardımcıları sil.
5. KPI/istatistik kutusu varsa `DsKpiTile` kullan, ekrana özel `_MetricCard`/`_MetricTile` benzeri widget'ları sil.
6. Boş durum için `EmptyStateCard`, yükleme için `Skeletonizer` kullan (bare `CircularProgressIndicator` yasak).
7. Filtre çubuğu varsa `SmartFilterBar`'a geçir (bkz. tasarım dokümanı §3.3 — bu bileşenin genişletilmesi ilgili ekran fazında yapılır).
8. Sayfa çerçevesi için `AppPageLayout` kullan; özel `Scaffold`/`AppBar` yalnızca gerekçelendirilmiş istisnalarda kalır.
9. Ham `Color(0x...)`/`Colors.*` kullanımı varsa `AppTheme` semantic token'ına taşı.
10. Görsel diff / ekran görüntüsü ile önce-sonra karşılaştırması yapıp onaya sun.

## Sıra

Dashboard → İş Emirleri → Müşteriler → E-Fatura → Servis → Stok → Raporlar.
