# Dashboard v2 — Uygulama Raporu (Konsept C / Hibrit)

Durum: Uygulandı. Kapsam yalnızca `/panel` (Dashboard) ekranı — diğer 33 ekrana dokunulmadı.

## Değiştirilen / eklenen dosyalar

| Dosya | Değişiklik |
|---|---|
| `lib/features/dashboard/dashboard_screen.dart` | Tamamen yeniden düzenlendi (UI/UX katmanı). Business logic, provider çağrıları, yetki kontrolleri, banka şifresi/döviz kuru mantığı **birebir korundu**. |
| `lib/design_system/ds_kpi_tile.dart` | Kanonik bileşene `subtitle`/`subtitleColor` alanı eklendi (Açık Faturalar kartının tutar alt metni için gerekliydi — eksik özellik önce bileşende genişletildi, ekrana özel yeni kart yazılmadı). |
| `lib/design_system/status_tone.dart`, `ds_tokens.dart` | Değişmedi, ilk kez gerçek ekrana bağlandı. |

Not: Değişiklik geçmişi git ile korunuyor (`git diff`/`git log`) — ayrı bir dosya yedeği alınmadı, ihtiyaç halinde `git checkout -- lib/features/dashboard/dashboard_screen.dart` ile eski hâle dönülebilir.

## Ne değişti, neden

**Kaldırıldı**
- Sahte sparkline (`_MetricSparklinePainter`) — ARGB/hash tabanlı, gerçek veriyle ilişkisiz üretim tamamen kaldırıldı. Yeni `DsKpiTile` yalnızca gerçek bir zaman serisi verildiğinde sparkline çizer; bu ekranda hiçbir KPI'ya sahte/gerçek sparkline verilmedi (7 KPI'nın hiçbiri günlük seri olarak mevcut değil, yalnızca anlık sayı/tutar).
- İş Emri Pasta Grafiği (`_WorkOrderPieChart`, `_LegendItem`) — KPI kutularıyla bilgi tekrarı yarattığı için `_WorkOrderStatusBar` (stacked bar + `status_tone` tabanlı lejant) ile değiştirildi.
- Eski `_MetricsGrid`/`_MetricTile` (13 kart yüzeyi, başlıksız düz `Wrap`) — yerine bölüm başlıklı iki KPI grubu geldi.

**Yeniden düzenlendi**
- Bilgi mimarisi iki bölüme ayrıldı: **Bugün** (Açık İş Emirleri, Bugünkü İşler, Devam Eden, Yakında Süresi Dolacaklar) ve **Genel Bakış** (Açık Faturalar, Gelir (Bu Ay), Toplam Müşteri) — toplam 7 KPI, hepsi `DashboardMetrics`'te bugün gerçekten var olan alanlar (`openWorkOrders`, `todayWorkOrders`, `inProgressWorkOrders`, `expiringSoon`, `openInvoices`+`totalInvoiceAmount`, `revenue`+`revenueChangePercent`, `totalCustomers`). Yeni alan üretilmedi.
- Renk mantığı `status_tone`'un 5 tonuna indirgendi: sayma amaçlı KPI'lar (iş emri sayıları, fatura sayısı, müşteri sayısı, gelir) `info` (mavi) tonunda — bunlar normal iş hacmidir, alarm değildir. Yalnızca "Yakında Süresi Dolacaklar" gerçekten dikkat gerektiren bir metrik olduğu için `>0` ise `warning`, `0` ise `neutral`. Eskiden "Açık İş Emirleri" gibi normalde her zaman pozitif olan sayılar da amber oluyordu (alarm yorgunluğu); bu düzeltildi.
- "Gelir (Bu Ay)" kartında artık gerçek `revenueChangePercent` (bu ay/geçen ay karşılaştırması, mevcut hesaplanmış alan) ok yönlü yüzde rozeti olarak gösteriliyor — sahte değil, provider'da zaten hesaplanan gerçek bir değer.
- Banka Şifreleri ve Döviz Kurları, ana içgörülerin (KPI'lar, gelir grafiği, iş emri dağılımı, aktiviteler) **altına**, "Yardımcı Bilgiler" başlığı altına taşındı; kart içi boşluk 16px→12px, ikon 36px→32px küçültülerek daha az görsel ağırlık verildi. Şifre üretim mantığı ve döviz kuru sorgusu birebir aynı kaldı.
- Üç grafik kartındaki tekrar eden ikon+başlık header bloğu tek bir `_InsightCardHeader` bileşeninde toplandı (kod tekrarı azaltıldı, görünüm aynı ailede).

**Eklendi**
- `_DashboardSectionHeader` — "Bugün" / "Genel Bakış" / "Yardımcı Bilgiler" bölüm başlıkları, kartları gruplu hale getiriyor.
- `_KpiGrid` — masaüstünde satır başına en fazla 4, dar ekranda sabit 2 sütun (kural: `width >= 1024 → 4, aksi halde 2`, `ds_tokens.DsBreakpoints.desktop` kullanılarak).
- `_WorkOrderStatusBar` + `_StatusSegment` — `DsStatusDot`/`dsStatusToneColor` (status_tone.dart) ile boyanan gerçek oranlı stacked bar.

## Platform yerleşimi

**Web / Electron** (aynı bilgi mimarisi): ≥980px'te (`DsBreakpoints.filterBarWide`) gelir grafiği + iş emri stacked bar sol sütunda (flex 3), aktivite listesi sağ sütunda (flex 2). KPI grid'i ≥1024px'te 4 sütun.

**Mobil (iOS/Android/dar web)**: KPI'lar 2 sütunlu grid (Bugün önce, Genel Bakış sonra), <980px'te içerik tek sütun ve sıralama gelir grafiği → iş emri dağılımı → aktivite listesi (aktiviteler grafiklerden sonra, kural gereği). `ListView` alt padding'i (120px) korunduğu için alt navigasyon/FAB hiçbir içeriği kapatmıyor. Yatay taşma riski taşıyan yeni bir `Row` eklenmedi — Yardımcı Bilgiler kartları tüm platformlarda tam genişlik/dikey istiflenmiş kaldı (overflow riski yok).

## Tema

`themeModeProvider`/`AppTheme` hiç değiştirilmedi; tüm yeni bileşenler mevcut `AppTheme` semantic token'larını (`categoryIconWell`, `softTint`, `textMuted`, `success`/`warning`/`error` vb.) kullanıyor, Light/Dark/Auto otomatik olarak çalışmaya devam ediyor.

## Business logic / veri akışı

Dokunulmadı: `dashboardMetricsProvider`, `dashboardRevenueSeriesProvider`, `dashboardActivitiesProvider`, `dashboardHalkbankRatesProvider`, yetki kontrolleri (`hasPageAccessProvider`, `hasActionAccessProvider`, `kActionDashboard*`), banka şifre formülleri (`_isbankPassword`/`_garantiPassword`) birebir aynı. Yalnızca ekranda **kullanılmayan** iki yetki bayrağı (`kActionDashboardLowStock`, `kActionDashboardInvoiceQueue`) artık bu ekranda okunmuyor çünkü ilgili iki kutu (Düşük Stok, Fatura Kuyruğu) 7 KPI'lık yeni sete dahil edilmedi — bu, izin sisteminde değil yalnızca ekranın hangi bayrakları tükettiğinde bir değişiklik.

## Doğrulama notu (önemli, dürüstlük için)

Bu oturumdaki sanal Linux kabuğu (bash sandbox) bu görev boyunca başlatılamadı; bu yüzden `flutter format` / `flutter analyze` / `flutter build` komutlarını gerçekten çalıştıramadım. Bunun yerine dosyayı satır satır elle denetledim: tüm import'lar kullanılıyor, kaldırılan widget'lara (`_MetricsGrid`, `_MetricTile`, `_WorkOrderPieChart` vb.) başka hiçbir dosyadan referans yok (private/dosyaya özeldi), yeni bileşenlerin (`AppTheme.categoryIconWell/Fg`, `AppCard.onTap`, `DsKpiTile`, `DsStatusDot`, `dsStatusToneColor`) imza/parametreleri kaynak dosyalarından teyit edilerek kullanıldı. Yine de gönül rahatlığı için sizin ortamınızda `flutter analyze` ve `flutter build web` (veya ilgili hedef) çalıştırmanızı öneririm — bir sorun çıkarsa hemen düzeltirim.

## Sırada

Onayınızla İş Emirleri ekranına geçilecek (bkz. `lib/design_system/README.md` sıra listesi).
