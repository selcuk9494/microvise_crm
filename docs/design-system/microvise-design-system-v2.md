# Microvise Design System v2

Durum: Taslak — onay bekliyor. Hiçbir ekran bu doküman onaylanmadan değiştirilmeyecek.
Referans seviye: Linear, Stripe Dashboard, Microsoft 365 Admin, ClickUp.
Kapsam: Web (ve onu saran Electron masaüstü kabuğu), iOS, Android — tek Flutter kod tabanı, tek tema, platforma göre yalnızca yoğunluk/etkileşim/navigasyon adaptasyonu.

Bu sistem mevcut `AppTheme` (Ink Rail mavi/lacivert kimlik) üzerine inşa edilir — marka rengi değişmiyor. Amaç sıfırdan yeniden yaratmak değil, Faz 0 denetiminde tespit edilen tutarsızlıkları (4 farklı durum rozeti, kullanılmayan bileşenler, token bypass'ları, tutarsız boş/yükleme durumları) tek bir kaynağa indirgemek ve masaüstü/mobil arasında kasıtlı bir adaptasyon modeli tanımlamak.

---

## 0. Tasarım ilkeleri

1. **Tek kaynak, çok yüzey.** Bir bileşen bir kez tanımlanır; İş Emirleri, Servis, Faturalar aynı durum rozetini, aynı boş durumu, aynı filtre çubuğunu kullanır. İkinci bir "neredeyse aynı" implementasyon yasak.
2. **İçgörü önce, liste sonra.** Her ana ekran, ham tabloya geçmeden önce bir özet/rollup katmanı sunar (KPI, gruplama, trend). Bugün bunu sadece Dashboard ve Raporlar yapıyor; kural haline gelmeli.
3. **Yoğunluk platforma göre ayarlanır, hiyerarşi değişmez.** Masaüstünde daha fazla bilgi yan yana; mobilde aynı bilgi mimarisi daha az sütun/daha çok kaydırma ile. KPI şeridi mobilde küçülür, kaybolmaz (Servis ekranındaki bugünkü hata).
4. **Sessiz marka.** Renk sadece anlam taşır (durum, aksiyon, marka vurgusu). Dekoratif gradyan/gölge/renk yok; Ink Rail'in "keskin, güvenilir kurumsal" hissi korunur.
5. **Erişilebilirlik pazarlık konusu değil.** WCAG AA kontrast, ≥44pt dokunma hedefi (mobil), klavye/tab sırası (masaüstü), `flutter_animate` ile hareket her zaman `reduceMotion`'a saygılı.

---

## 1. Token katmanları

Üç katman: **Primitive** (ham renk/ölçü değerleri, sadece `app_theme.dart` içinde yaşar) → **Semantic** (anlam taşıyan token: `surface`, `textMuted`, `danger`) → **Component** (bir bileşene özel: `badgeBg`, `kpiIconWell`). Ekran kodu asla primitive'e dokunmaz, sadece semantic/component token kullanır. Bu kural bugün ihlal ediliyor (Stok, Personel, Giriş ekranlarında ham `Color(0x...)` — bkz. denetim raporu §3); v2'nin en kritik kuralı budur.

### 1.1 Renk — Light / Dark / Auto

Auto zaten doğru kurulmuş (`themeModeProvider`, `ThemeMode.system`, tercih `AppCache`'te kalıcı) — bu katman değişmiyor, sadece aşağıdaki semantic tabloya bağlanıyor.

Mevcut Ink Rail (light) ve Warm Charcoal (dark) paletleri korunuyor, üstüne 3 eksik semantic katman ekleniyor:

| Semantic token | Light | Dark | Kullanım |
|---|---|---|---|
| `surface.0` (canvas) | `background` (#F4F6F8) | `background` (#18181B) | Sayfa zemini |
| `surface.1` (card) | `surface` (#FFFFFF) | `surface` (#27272A) | Kart/panel |
| `surface.2` (raised) | `surfaceSoft` (#E8ECF0) | `surfaceSoft` (#2E2E32) | Popover, menü, aktif satır |
| `surface.3` (overlay) | beyaz + `cardShadow` | `surface` + 1px border, gölge yok | Dialog, bottom sheet |
| `status.info` | `blue` #2563EB | `blueBright` #60A5FA | Bilgi rozeti/banner |
| `status.success` | `success` #16A34A | #22C55E | Başarılı/aktif |
| `status.warning` | `warning` #D97706 | #F59E0B | Beklemede/dikkat |
| `status.danger` | `error` #DC2626 | #EF4444 | Hata/iptal/gecikme |
| `status.neutral` | `textMuted` #6B7280 | #A1A1AA | Taslak/pasif/arşiv |

**Kural**: Bir ekranda "durum" göstermek gerektiğinde bu 5 tondan biri seçilir — yeni renk türetilmez. Bu tablo `StatusTone` enum'una birebir eşlenir (bkz. §3.1).

### 1.2 Tipografi

Inter korunuyor. Mevcut `textTheme` isimlendirmesi (Material `headlineSmall`/`titleLarge`/…) iç kod için kalsın, ama tasarım dilinde şu adlarla anılır:

| Rol | Boyut / Ağırlık | Karşılık gelen Material stil |
|---|---|---|
| Display | 28 / 700, -0.4 ls | yeni: `displaySmall` override |
| H1 (sayfa başlığı) | 22 / 700 | `headlineSmall` |
| H2 (bölüm başlığı) | 18 / 700 | yeni ara kademe |
| H3 (kart başlığı) | 16 / 600 | `titleMedium` |
| Body | 15 / 400 | `bodyLarge` |
| Body Soft (ikincil) | 13 / 400 | `bodyMedium` |
| Caption | 11.5 / 400 | `bodySmall` |
| Label (buton/rozet) | 13 / 600 | `labelLarge` |
| Overline (tablo başlığı) | 11 / 600, +0.4 ls, UPPERCASE | yeni |
| **Numeric / Tabular** | Inter, `FontFeature.tabularFigures()` | yeni — tüm para/miktar/tarih sütunlarında zorunlu |

Bugün hiçbir ekran tabular figures kullanmıyor; bu, tablo/liste ekranlarındaki sayı sütunlarının "kayması" hissinin en ucuz çözümüdür ve Dashboard fazında ilk uygulanacak kurallardan biri.

### 1.3 Spacing, radius, elevation, motion

- **Spacing grid**: 4pt taban — 4/8/12/16/20/24/32/40/48. Bugünkü kod zaten çoğunlukla 4'ün katları kullanıyor (Gap widget'ları); resmileştiriliyor, serbest sayı (ör. 14, 18) yalnızca padding iç boşluğunda istisna.
- **Radius**: mevcut ölçek (`radiusXs=8, radiusSm=12, radiusMd=16, radiusLg=20, radiusXl=24`) korunuyor. Kural: kart=Md, buton/input=Xs, dialog/sheet=Lg, rozet/chip=999 (pill).
- **Elevation** (yeni, bugün sadece iki durum var: gölgeli/gölgesiz):
  - `elevation.0` — zemin (gölge yok)
  - `elevation.1` — kart (mevcut `cardShadow`)
  - `elevation.2` — hover/dropdown (mevcut `hoverShadow`)
  - `elevation.3` — dialog/sheet/popover (yeni: blur 24, offset 0/8, alpha 0.08 light / border-only dark)
- **Motion** (yeni token seti):
  - `duration.instant` 100ms — hover/basma geri bildirimi
  - `duration.fast` 160ms — mevcut sidebar/nav geçişleri (zaten bu değeri kullanıyor)
  - `duration.base` 220ms — sayfa içi genişleme/daralma (AnimatedCrossFade, filtre paneli)
  - `duration.slow` 320ms — sayfa geçişi, modal açılış
  - Easing: `Curves.easeOut` giriş, `Curves.easeIn` çıkış — bugün kod zaten `easeOut` kullanıyor, resmileştiriliyor.

---

## 2. İkonografi

Bugün Material Icons (outlined/rounded karışık) + Phosphor birlikte kullanılıyor. v2 kuralı: **navigasyon ve durum ikonlarında `Icons.*_rounded` ailesi birincil**, Phosphor yalnızca özel/dekoratif ikon gerektiğinde (ör. boş durum illüstrasyonu) kullanılır. Boyutlar: nav 19-21px, buton içi 16-18px, KPI/empty-state well 20-24px, tablo satır aksiyonu 18px. Tutarsız karışık kullanım (bazı ekranlarda `_outlined`, bazılarında `_rounded`) tek aileye (`_rounded`) indirilir.

---

## 3. Bileşen envanteri (kanonik, tek versiyon)

Aşağıdakiler mevcut `lib/core/ui/*` bileşenlerinin **yerini almaz**, onları konsolide eder. Her biri için "bugün kaç versiyon var → v2'de kaç versiyon olacak" belirtiliyor.

### 3.1 Durum / Rozet — `StatusTone` + `DsStatusBadge` / `DsStatusDot`

Bugün: 4 paralel implementasyon (AppBadge, `_compactStatusPill`, `_StatusPill`, kanban inline switch), aynı durum 3 farklı etiketle gösteriliyor. v2'de: tek `StatusTone` enum (`info/success/warning/danger/neutral`) + tek etiket sözlüğü (durum kodu → TR etiket, tek yerde tanımlı) + 3 sunum modu (badge/pill, dot, tablo hücresi metni) aynı tondan türer. İş Emirleri ve Servis ekranları bu faza geçtiğinde diğer tüm özel `_statusColor`/`_statusBadge` fonksiyonları silinir.

### 3.2 Boş / Yükleme / Hata durumları

Bugün: `EmptyStateCard` 2/16 ekranda, yükleme 2 farklı stratejide (Skeletonizer / CircularProgressIndicator), hata durumu ekran başına elle yazılmış. v2 kuralı: her liste/tablo ekranı 3 durumu da aynı sözleşmeyle sağlar — `DsAsyncState` sarmalayıcısı: `loading` → Skeletonizer (zorunlu, spinner yasak), `empty` → `EmptyStateCard` (ikon + başlık + mesaj + opsiyonel aksiyon, zorunlu), `error` → aynı kart ailesinde "Tekrar Dene" aksiyonlu hata görünümü (bugün sadece Müşteri Detay'da var, standart hale geliyor).

### 3.3 Filtre çubuğu — `DsFilterBar`

Bugün: `SmartFilterBar` yazılmış ama sıfır kullanım; 4 ekran aynı deseni bağımsız kopyalamış (980 vs 900px breakpoint farkı dahil). v2: `SmartFilterBar` tek breakpoint sabiti (980) ile genişletilir — arama, durum çip grubu, tarih aralığı, görünüm anahtarı (liste/kanban/grid) slotları standart sırayla. İş Emirleri, Servis, Personel, Müşteriler bu bileşene geçtiğinde kendi filtre kodlarını siler.

### 3.4 KPI / istatistik kartı — `DsKpiTile`

Bugün: Dashboard `_MetricTile` (sparkline'lı), Servis `_MetricCard`, kit içi `CompactStatCard` — 3 ayrı implementasyon. v2: tek `DsKpiTile` — ikon well + etiket + değer + opsiyonel trend (sparkline veya % delta oku) + opsiyonel tıklanabilirlik (ilgili listeye filtre uygulayarak gitme). Masaüstünde `Wrap` grid, mobilde yatay kaydırılabilir şerit (Servis'in bugün "1200px altında tamamen kaybolan" KPI şeridinin çözümü budur).

### 3.5 Yoğun liste satırı ve tablo — `AppDenseList` ailesi genişletiliyor

Bugün en olgun dosya ama sadece Müşteriler + E-Fatura kullanıyor. v2: `AppInvoiceTableCols` deseni genelleştirilip `DsTableColumnSpec` haline getiriliyor — her tablo ekranı (İş Emirleri, Personel, Faturalar, E-Fatura Formu satır tablosu) sabit piksel genişliğini elle yazmak yerine bu spec'i kullanır. Sayı/tarih sütunları §1.2'deki tabular figures kuralına tabidir.

### 3.6 Sayfa çerçevesi — `AppPageLayout` zorunlu hale geliyor

`customer_detail_screen` ve `e_invoice_form_screen`'in bugün kendi `Scaffold`/`AppBar`'ını kurması istisna değil kural dışı davranış olarak işaretleniyor. v2: `AppPageLayout`'a bir `detail` varyantı eklenir (geri butonu + kompakt başlık + aksiyon slotu), böylece detay/form ekranları da aynı üst çerçeveyi kullanır, özel `AppBar` yazmaz.

### 3.7 Form düzeni — `DsFormSection`

Bugün formlar (İş Emirleri oluşturma diyalogu, Tanımlamalar) düz `TextFormField` yığını. v2: formlar `DsFormSection` ile mantıksal bloklara ayrılır (başlık + ilgili alan grubu + ince ayırıcı), iki sütunlu masaüstü / tek sütun mobil otomatik geçiş. Bu, "kurumsal form" hissi ile "düz CRUD formu" hissi arasındaki en büyük farktır (Stripe/Linear formlarının karakteristik özelliği).

---

## 4. Navigasyon ve kabuk (`AppShell`)

Mevcut kabuk mimarisi (masaüstü sidebar + daraltılabilir ikon rayı, mobil bottom-nav + FAB + modül sheet'i) **korunuyor** — zaten sektör standardına yakın. v2'nin eklediği tek şey: sidebar aktif durum/renk mantığının (`_navAccentColor`, `sidebarNavDecoration`) `StatusTone` sisteminden ayrı ama tutarlı bir "nav accent" token setine bağlanması ve masaüstü top bar'a global arama (⌘K tarzı komut paleti) için bir yer ayrılması — bu, Linear/Stripe seviyesi bir üründe beklenen ve bugün eksik olan tek büyük navigasyon özelliği. Komut paleti implementasyonu bu fazın kapsamı dışında; sadece token/yer planlaması burada yapılıyor.

---

## 5. Platform adaptasyonu

Tek kod tabanı, tek `AppTheme` — aşağıdakiler *görsel dil* değil, *etkileşim* farkları:

### Web / Electron (masaüstü)
- Fare öncelikli: hover state zorunlu (AppCard zaten yapıyor, tüm yeni bileşenler de yapmalı).
- Yoğunluk yüksek: KPI grid 4-5 sütun, tablo tüm sütunları gösterir.
- Klavye: Tab sırası mantıklı, `Escape` dialog/sheet kapatır, gelecekte ⌘K komut paleti.
- Electron sarmalayıcısı native pencere çerçevesi kullanıyor (custom title bar yok) — bu fazda değişmiyor.

### iOS / Android
- Dokunma hedefi ≥44pt (bugün bazı ikon butonları 38px — `iconButtonTheme.minimumSize` gözden geçirilecek).
- Yoğunluk düşük: KPI şeridi yatay kaydırma, tablo → kart listesi (Müşteriler'in bugün yaptığı gibi, genel kural haline geliyor).
- Native transition: `CupertinoPageTransitionsBuilder` iOS'ta zaten aktif — korunuyor.
- Bottom sheet, iOS'ta modal yerine tercih edilen birincil "ikincil aksiyon" yüzeyi (bugün zaten çoğunlukla böyle).
- Haptic geri bildirim: kritik aksiyonlarda (silme, durum değiştirme) `HapticFeedback.lightImpact()` — bugün hiç kullanılmıyor, öneri olarak ekleniyor, zorunlu değil.

---

## 6. Bu fazda teslim edilen kod (ekran değişikliği YOK)

Yalnızca aşağıdaki yeni, katkı-amaçlı (additive) dosyalar eklendi — mevcut hiçbir ekran veya `core/ui` dosyası değiştirilmedi/silinmedi, hiçbir import bağlanmadı, uygulama davranışı değişmedi:

- `lib/design_system/ds_tokens.dart` — spacing/radius/elevation/motion sabitleri
- `lib/design_system/status_tone.dart` — kanonik `StatusTone` enum + Türkçe etiket sözlüğü + `DsStatusBadge`/`DsStatusDot`
- `lib/design_system/ds_kpi_tile.dart` — kanonik KPI kartı (sparkline destekli)
- `lib/design_system/README.md` — benimseme planı ve ekran başı geçiş kontrol listesi

Bu bileşenler Dashboard fazında ilk kez gerçek ekrana bağlanacak; onaylanmadan hiçbir mevcut dosyaya dokunulmayacak.

---

## 7. Sıradaki adımlar

1. Bu doküman onaylanır.
2. Dashboard ekranı: önce mevcut tasarım eleştirisi, sonra ≥3 konsept, sonra seçilen konseptin uygulanması (yalnızca UI katmanı, business logic/API dokunulmaz).
3. Onaydan sonra sırayla: İş Emirleri → Müşteriler → E-Fatura → Servis → Stok → Raporlar.
