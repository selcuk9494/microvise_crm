# Microvise CRM — UI/UX Audit (Faz 0)

Tarih: 2026-08-02
Kapsam: Tüm ekranlar değiştirilmeden önce mevcut mimarinin ve 34 ekranın objektif dökümü. Hiçbir kod değişikliği içermez.

## Genel değerlendirme

Beklenenin aksine, altyapı "sıradan CRUD" seviyesinin üzerinde: `AppTheme` olgun bir token sistemi (iki palet, radius/shadow/chip ölçeği, tam `ThemeData` kablolaması), `AppShell` gerçek responsive bir kabuk (masaüstü daraltılabilir sidebar, mobil bottom-nav + FAB + modül sheet'i, light/dark/auto tema anahtarı zaten çalışıyor), `AppPageLayout` paylaşılan sayfa çerçevesi sağlıyor. Sorun; bu iyi temelin ekranlar arasında **tutarlı uygulanmamış** olması. Aynı problem (durum rozeti, boş durum, filtre çubuğu, KPI kartı) 3-5 farklı şekilde çözülmüş; bazı ekranlar zaten kurulan bileşenleri hiç kullanmıyor.

## 1. Paylaşılan UI kiti (`lib/core/ui/*.dart`)

- **AppCard** — hover-lift animasyonlu temel yüzey. Tutarlı kullanılıyor ama esnek olmadığı için ekranlar çoğu zaman onu extend etmek yerine yanından yeni `Container` dekorasyonu yazıyor.
- **AppSectionCard** — başlık/alt başlık/trailing kalıbı. Sadece birkaç ekran kullanıyor; çoğu liste ekranı kendi başlık bloğunu inline yazıyor.
- **AppBadge** — 5 ton (`softTint`/`softBorder`/`softFg`) ile en tutarlı kullanılan bileşen. Buna rağmen İş Emirleri kendi `_compactStatusPill` + `_StatusPill` widget'larını paralel olarak tanımlıyor.
- **EmptyStateCard** — iyi tasarlanmış boş durum bileşeni, ama 16 ekrandan sadece 2'sinde (Müşteriler, Stok) kullanılıyor. Diğerleri (İş Emirleri, Servis, Faturalama, Faturalar, Personel, Tanımlamalar) kendi boş-durum metnini/kartını elle yazıyor.
- **SmartFilterBar** — tam olarak ihtiyaç duyulan filtre çubuğu paterni için yazılmış ama **hiçbir ekranda kullanılmıyor**. İş Emirleri, Servis, Personel, Müşteriler aynı deseni (AppCard + LayoutBuilder + Wrap) dört kez birbirinden bağımsız olarak yeniden yazmış.
- **CompactStatCard** — Dashboard kendi `_MetricTile`'ını (sparkline dahil) ayrı yazmış; Servis kendi `_MetricCard`'ını ayrı yazmış. Üç farklı "küçük istatistik kutusu" implementasyonu var.
- **AppDenseList** — kitin en olgun dosyası (yoğunluk token'ları, `AppInvoiceTableCols`, `AppDenseListCard`). Sadece Müşteriler ve E-Fatura kullanıyor; en karmaşık ekran olan İş Emirleri bunu hiç kullanmıyor, kendi satır bileşenlerini yazmış.

**Sonuç**: bileşenler CRUD şablonundan daha kaliteli, ama benimseme oranı düşük. En çok tekrar eden iki ekran (İş Emirleri, E-Fatura) en çok "paralel özel kod" taşıyan ekranlar.

## 2. Ekran bazlı bulgular (özet)

| Ekran | Durum |
|---|---|
| Dashboard | Gerçek içgörü katmanı var (metrik grid + gelir grafiği + pasta grafik + aktivite akışı). Ama 3 widget kartı (banka şifreleri, döviz kurları, vs.) neredeyse birebir aynı header kalıbını kopyala-yapıştır olarak 3 kez içeriyor. |
| İş Emirleri (Liste) | En büyük ekran (2400+ satır). Durum renk/etiket mantığı dosya içinde 3 kez tekrarlanmış. Oluşturma diyalogu düz bir Form — görsel gruplama yok. Boş durum `EmptyStateCard` değil. |
| İş Emirleri (Kanban) | Aynı veriyi 3. bir UI paradigmasıyla (drag&drop kanban) gösteriyor; liste ekranıyla satır bileşenini paylaşmıyor — 4-5. bağımsız "iş emri satırı" implementasyonu. |
| Müşteriler | En iyi hizalanmış ekranlardan biri: gerçek mobil/masaüstü ayrımı, sayfalama, Excel import/export, `EmptyStateCard` doğru kullanılmış. |
| Müşteri Detay | `AppPageLayout` yerine özel `Scaffold`+geri butonu kullanıyor; 6 sekmeye her şeyi sıkıştırma eğilimi var, üstte özet/rollup yok. |
| E-Fatura | Faydalı bir durum şeridi var (VKN/ortam/kimlik durumu) ama bu pattern başka hiçbir ekranda yok. Sekmeler `TabBar` değil route parametresiyle yönetiliyor — sekme görünürlüğü yok. |
| E-Fatura Formu | Gerçek masaüstü/mobil ayrımı olan nadir ekranlardan (mobilde alt kaydetme çubuğu). Kendi fatura satırı tablosunu yazmış, `AppInvoiceTableCols`'u kullanmıyor. |
| Servis | İş Emirleri'nin yapısal ikizi — aynı tekrarlar. KPI şeridi sadece ≥1200px'te görünüyor, mobilde özet katmanı tamamen kayboluyor (daralmıyor, yok oluyor). |
| Servis Detay | Zengin domain ekranı (imza, fotoğraf, parça/işçilik) ama hata/bulunamadı durumu tek satır, yeniden dene aksiyonu yok. |
| Stok | Kitle iyi hizalı ama `AppTheme.textMuted` yerine ham `Color(0xFF94A3B8)` gibi token bypass'ları var. Sayfalama yok. |
| Raporlar | Dashboard'daki grafikle neredeyse birebir aynı ama ayrı kod olan bir çizgi grafik kullanıyor. Drill-down/export yok. |
| Giriş | Kendi lokal `Theme` override'ını taşıyor, `app_theme.dart`'tan bağımsız; token dışı sabit renk var. |
| Faturalama | Düz liste, özet katmanı yok, boş durum kendi elle yazılmış. |
| Faturalar | Sekmeler için tema dışı özel stil; 4. farklı boş-durum implementasyonu. |
| Personel | En "ham CRUD tablosu" hisseden ekran: sabit piksel genişlikli sütunlar, token dışı sabit renkler, kart yerine düz `Divider` ile ayrılmış satırlar. |
| Tanımlamalar | 9 sekmeli, sabit/clamp'lenmiş yükseklik (magic number) — responsive anti-pattern. Her sekme kendi yerel boş-durum widget'ını tekrar yazmış. |
| Formlar | En temiz ekran; veri yoğunluğu az olduğu için kitin potansiyelini en iyi gösteren örnek. |

## 3. Ekranlar arası tutarsızlıklar

- **Durum/rozet gösterimi**: en az 4 paralel implementasyon (AppBadge, `_compactStatusPill`, `_StatusPill`, kanban'ın inline switch'i). Aynı durum değeri ekrana göre farklı etiketleniyor ("BEKLEYEN" / "Açık" / "open").
- **Boş durumlar**: 16 ekrandan sadece 2'si `EmptyStateCard` kullanıyor.
- **Yükleme durumları**: Skeletonizer bazı ekranlarda var, bazılarında düz `CircularProgressIndicator` — kural yok, kim son dokunduysa öyle kalmış.
- **Sayfa çerçevesi**: çoğu ekran `AppPageLayout` kullanıyor ama detay/form ekranları (Müşteri Detay, E-Fatura Formu) bunun dışına çıkıp kendi `Scaffold`/`AppBar`'ını kuruyor.
- **Filtre çubukları**: `SmartFilterBar` var ama kullanılmıyor; 4 ekran aynı deseni birbirinden bağımsız (ve birbirinden hafif farklı breakpoint'lerle: 980 vs 900) yeniden yazmış.
- **Token bypass**: 29 dosyada 122 ham `Color(0x...)`, 31 dosyada 115 ham `Colors.*` referansı tespit edildi (grep). Örnekler: Stok, Personel, Giriş, İş Emirleri.
- **Tablo paterni**: Hiçbir ekran Flutter'ın `DataTable`'ını kullanmıyor (doğru tercih) ama her ekran kendi sabit piksel sütun genişliğini elle tanımlıyor; sadece fatura tablosu için ortak bir sütun spesifikasyonu (`AppInvoiceTableCols`) var ve o bile tutarlı kullanılmıyor.

## 4. Responsive gerçeklik kontrolü

Gerçek (sadece reflow değil) mobil/masaüstü ayrımı olan ekranlar: Dashboard, Müşteriler, İş Emirleri Liste, E-Fatura Formu, Formlar.

Sadece aynı masaüstü içeriğini sıkıştıran/taşan ekranlar: Servis (KPI şeridi 1200px altında tamamen kayboluyor), Faturalama, Faturalar, Raporlar, Personel, Tanımlamalar (9 sekme + magic-number yükseklik clamp'i — küçük ekranlarda özellikle kırılgan), Müşteri Detay (6 sekme genişlikten bağımsız aynı).

## 5. Veri yoğunluğu / hiyerarşi kontrolü

Gerçek özet/içgörü katmanı olan ekranlar: Dashboard (en iyi örnek), Raporlar, Servis (sadece masaüstünde), İş Emirleri (rozet şeridi, grafik değil).

Salt liste/tablo, özet katmanı olmayan ekranlar: Faturalama, Faturalar, Personel, Tanımlamalar, Müşteri Detay (6 sekme ama üstte "toplam aktif hat", "en yakın lisans bitişi" gibi bir rollup yok).

---

Bu doküman kod değişikliği içermez; sıradaki adım bu bulgulara dayanan **Microvise Design System v2** spesifikasyonudur.
