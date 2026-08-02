# Dashboard Fazı — Eleştiri ve Konseptler (Faz 1, Adım 1)

Durum: Onay bekliyor. Hiçbir dosya değiştirilmedi. Bu doküman yalnızca analiz ve öneridir.

Kapsam notu: Electron sarmalayıcısı `flutter build web` çıktısını aynen barındırıyor (bkz. denetim raporu, `electron/main.js`) — native bir masaüstü UI'ı yok. Bu yüzden **Web ve Electron için bilgi mimarisi ve yerleşim birebir aynıdır**; aşağıda yalnızca gerçekten farklılaşan noktalar (pencere/varsayılan genişlik davranışı) ayrıca belirtiliyor, geri kalan her yerde "Web/Electron" tek başlık altında ele alınıyor.

Veri kaynağı notu (önemli): Aşağıdaki tüm eleştiri ve konseptler yalnızca `dashboard_providers.dart`'ta bugün gerçekten var olan alanları kullanır: `DashboardMetrics` (totalCustomers, openWorkOrders, inProgressWorkOrders, completedWorkOrders, todayWorkOrders, expiringSoon, totalProducts, lowStockProducts, revenue, lastMonthRevenue, revenueChangePercent, todayCollections, totalReceivable, totalPayable, openInvoices, totalInvoiceAmount, invoiceQueuePending), `dashboardRevenueSeriesProvider` (gerçek 14 günlük tahsilat serisi), `dashboardActivitiesProvider` (gerçek son 8 iş emri/servis aktivitesi), `dashboardHalkbankRatesProvider` (döviz), Banka Şifreleri (tarihe dayalı yerel hesap). Yeni alan uydurulmadı.

---

## A. Mevcut Dashboard Eleştirisi

### 1. Bilgi hiyerarşisi
Sıralama bugün: KPI grid (5-9 kutu) → **Banka Şifreleri** → **Döviz Kurları** → Gelir grafiği / İş Emri Durumu / Aktiviteler (satır 82-111'de kod sırası budur). Şirketin gerçek işini anlatan üç içerik bloğu (gelir trendi, iş emri dağılımı, aktivite akışı) iki kişisel/yardımcı araç kartının (banka şifresi kısayolu, döviz kuru referansı) **altında** kalıyor. Bilgi mimarisi önem sırasına göre değil, kod yazılma sırasına göre kurulmuş.

### 2. KPI kartlarının okunabilirliği
En kritik bulgu: her KPI kutusunun sağındaki mini sparkline (`_MetricSparklinePainter`, satır 1035-1076) **gerçek veriyle hiçbir ilişkisi olmayan**, rengin ARGB değerinden türetilen sahte bir dalga deseni çiziyor (`seed = color.toARGB32()`). Yani "Toplam Müşteri" ve "Açık İş Emirleri" kutularındaki eğri satışta artış/azalış gösteriyormuş gibi görünüyor ama aslında rastgele/dekoratif. Bu, kullanıcıyı yanıltan bir tasarım hatası ve sizin de kurallarınızdan biriyle ("sparkline yalnızca gerçek anlamlı veri varsa") doğrudan çelişiyor. Ayrıca dar genişliklerde (2 sütun, ~560-720px) ikon+başlık+değer+alt metin+sahte sparkline tek satıra sıkışıyor, başlık ve değer elipslenmeye başlıyor.

### 3. Gereksiz boşluklar ve aşırı büyük alanlar
Banka Şifreleri ve Döviz Kurları kartları tam genişlik, 16px iç boşluklu, tek satır bilgi (başlık + alt metin + ok ikonu) taşıyor — çok boşluğa çok az bilgi. Grafik kartlarında ikon+başlık header bloğu (36x36 ikon kutusu + başlık + açıklama) gerçek grafikten önce sabit ~60-70px dikey alan tüketiyor; üç kartta da (Gelir, İş Emri Durumu, Aktiviteler) neredeyse birebir aynı header tekrarlanıyor.

### 4. Kart sayısı ve görsel yoğunluk
Rol izinlerine göre 5-9 KPI kutusu + Banka Şifreleri + Döviz Kurları + Gelir grafiği + İş Emri Pasta Grafiği + Aktiviteler = tek ekranda **13'e kadar ayrı kart yüzeyi**, her biri kendi border+gölge+ikon-well header'ıyla. Aralarında hiçbir bölüm başlığı ("Bugün", "Bu Ay", "Genel Bakış" gibi) yok — hepsi aynı görsel ağırlıkta yan yana/alt alta.

### 5. Renklerin fazla veya yanlış kullanıldığı yerler
"Açık İş Emirleri" kutusu `openWorkOrders > 0` ise amber oluyor (satır 819-821) — aktif bir işletmede bu sayı neredeyse her zaman >0, yani amber sürekli yanıyor ve anlamını kaybediyor (alarm yorgunluğu). "Devam Eden" hep `AppTheme.blue`, "Bugünkü İşler" hep `AppTheme.blueBright` — üç farklı KPI'da üç farklı mavi tonu (`metricBlue`/`blue`/`blueBright`) kullanılmış ama aralarında anlamsal bir fark yok, sadece görsel çeşitlilik için seçilmiş görünüyor. Kart header ikonları da (Banka Şifreleri→mavi, Döviz→turuncu, Aktivite→turuncu) durum değil, kart kategorisi için "dekoratif" renk taşıyor — bu, Design System v2'nin "renk yalnızca durum/öncelik belirtir" kuralıyla çelişen bugünkü alışkanlık.

### 6. Grafiklerin gerçekten faydalı olup olmadığı
Gelir çizgi grafiği (14 gün, gerçek veri) **gerçekten faydalı** — korunmalı. İş Emri pasta grafiği, üç durumun (açık/devam/tamamlanan) sayılarını zaten üstteki KPI kutularında ayrı ayrı gösterdiğimiz için kısmen tekrar niteliğinde; pasta grafik büyüklük karşılaştırmasında çizgi/çubuktan daha zayıf bir format. Aktivite akışı grafik değil ama gerçek ve faydalı bir liste. Sahte sparkline'lar (§2) faydasız, kaldırılmalı.

### 7. Mobil ekranda aşağı kaydırmayı artıran unsurlar
Mobilde (dar genişlik) KPI kutuları 1-2 sütuna düşüyor → 9 kutu 5-9 satıra yayılıyor, ardından Banka Şifreleri + Döviz Kurları + Gelir grafiği (240px) + Pasta grafiği (160px) + Aktivite kartı **hepsi tam genişlikte alt alta** (iki sütunlu masaüstü düzeni yalnızca ≥980px'te devreye giriyor, hiçbir telefon bu genişliğe ulaşmaz). Mobil kullanıcı, masaüstüyle aynı 13 bloğu, sadece tek sütunda ve daha uzun bir sayfa olarak kaydırmak zorunda kalıyor.

### 8. Web ile mobil arasındaki tasarım tutarsızlıkları
Masaüstünde ≥980px'te Gelir(3/5) + [Pasta+Aktivite](2/5) yan yana; mobilde aynı üç kart aynı sırayla dikey — bu "yanlış" değil ama kasıtlı bir mobil bilgi mimarisi değil, düz reflow. Anlamsız sparkline dekorasyonu, tam da mobilde kutuların en dar olduğu yerde ekstra yatay alan tüketmeye devam ediyor — mobilde kaldırılması gereken ilk öğe.

### 9. Kullanıcının ilk 5 saniyede anlaması gereken bilgiler
Bugün ilk ekranda "bugün" (Bugünkü İşler), "genel" (Toplam Müşteri, Düşük Stok) ve "bu ay" (Gelir) zaman ölçekleri hiç ayrılmadan aynı satırda karışık veriliyor. Kullanıcı 5 saniyede "bugün ne yapmam gerekiyor" ile "genel durum nedir"i birbirinden ayıramıyor çünkü görsel olarak hiçbir gruplama/bölüm başlığı yok.

### 10. Kaldırılması / birleştirilmesi / ikincil seviyeye alınması gerekenler
- **Kaldır**: Sahte sparkline dekorasyonu (`_MetricSparklinePainter`) — gerçek veri yok, kural ihlali.
- **İkincil seviyeye al**: Banka Şifreleri kartı — işle ilgili bir metrik değil, kişisel/yardımcı bir kısayol; tam genişlik satır yerine üst bar'da küçük bir hızlı-erişim öğesi olmalı.
- **İkincil seviyeye al**: Döviz Kurları kartı — referans bilgisi, karar metriği değil; küçük bir şerit/rozet grubuna indirilebilir.
- **Birleştir/değerlendir**: İş Emri Pasta Grafiği — üstteki Açık/Devam Eden/Tamamlanan KPI kutularıyla bilgi tekrarı; ya kaldırılıp KPI kutularına bir "toplam içindeki payı" ibaresi eklenebilir ya da grafik tipi çubuğa çevrilip KPI kümesiyle görsel olarak birleştirilebilir (bu, aşağıdaki konseptlerde ele alınıyor).

---

## B. Konseptler

Ortak platform kuralı (üç konsept için de geçerli): Web/Electron'da bilgi mimarisi birebir aynı, yalnızca pencere genişliğine göre KPI sütun sayısı ve iki-sütunlu içerik alanı davranır (Electron tipik olarak geniş pencerede açılır → çoğunlukla masaüstü düzeni). iOS'ta aynı bölüm sırası korunur, yoğunluk düşer: KPI'lar yatay kaydırılabilir 2 sütunlu kompakt grid, grafik kartları tam genişlik ve daha kısa varsayılan yükseklikte, "ikincil" bölümler (Döviz/Banka Şifreleri) bottom sheet'e taşınır.

---

### KONSEPT A — Operasyon Odaklı

**Öncelik**: Bugünkü işler, Açık iş emirleri, Süresi dolan işler, Bekleyen tahsilatlar, Kritik bildirimler.

**Veri dürüstlüğü notu**: Mevcut veri modelinde iş emri bazında "gecikmiş/süresi dolmuş" alanı yok (`overdue` yok); en yakın gerçek karşılık `expiringSoon` (lisans/hat süre dolumu, 30 gün içinde) ve `todayWorkOrders` (bugün planlı). "Kritik Bildirimler" için ayrı bir bildirim tablosu da yok; bu bölüm, bugün zaten var olan eşik mantığından (openWorkOrders, expiringSoon, lowStockProducts, invoiceQueuePending > 0 olduğunda amber/kırmızı olması) türetilen kısa bir "dikkat gerektirenler" özet listesi olarak kurgulanmıştır — yeni bir veri kaynağı icat edilmemiştir.

**Bölüm sıralaması**:
1. "Bugün" şeridi — Bugünkü İşler (todayWorkOrders) + Açık İş Emirleri (openWorkOrders) + Devam Eden (inProgressWorkOrders) + Süresi Dolanlar (expiringSoon) — 4 KPI.
2. Dikkat Gerektirenler — yukarıdaki eşiklerden derlenen kısa metin listesi (ör. "3 lisans 30 gün içinde doluyor", "Fatura kuyruğunda 5 kayıt bekliyor").
3. Finans anlık durum — Bugün Tahsil Edilen (todayCollections) + Bekleyen Tahsilat (totalReceivable) + Açık Faturalar (openInvoices, totalInvoiceAmount alt metin) — 3 KPI.
4. Son Aktiviteler (dashboardActivitiesProvider, gerçek liste).
5. Gelir (14 Gün) grafiği — ikincil konumda, referans amaçlı.
6. Döviz Kurları — kompakt şerit.
7. Banka Şifreleri — üst bar hızlı erişim (sayfa içi kart değil).

**Web yerleşimi**: 1200px+ genişlikte üstte 4'lü KPI şeridi tam genişlik; altında 2 sütun — sol (flex 3) Dikkat Gerektirenler + Son Aktiviteler, sağ (flex 2) Finans anlık durum KPI'ları + Gelir grafiği (küçük, referans boyutunda, 160px). Döviz şeridi sayfa altında ince bir bar.

**Electron yerleşimi**: Web ile birebir aynı; pencere genelde ≥1200px açıldığından varsayılan olarak 2 sütunlu görünüm.

**iOS yerleşimi**: 4 KPI kart 2x2 kompakt grid (yatay kaydırma yok, sabit 2 sütun — kuralınıza uygun). Ardından Dikkat Gerektirenler (tam genişlik liste), Finans KPI'ları (2x2 ikinci grid), Son Aktiviteler (tam genişlik liste), Gelir grafiği en altta katlanabilir/kısa. Döviz ve Banka Şifreleri üst bar ikonundan açılan bottom sheet'e taşınır, ana akışta yer kaplamaz.

**Kullanılacak KPI kartları**: Bugünkü İşler, Açık İş Emirleri, Devam Eden, Süresi Dolanlar, Bugün Tahsil Edilen, Bekleyen Tahsilat, Açık Faturalar. (7 KPI, iki gruba bölünmüş — hiçbiri sahte trend içermez.)

**Kullanılacak grafikler**: Yalnızca Gelir (14 Gün) çizgi grafiği (gerçek veri) — ikincil/küçük boyutta. İş Emri Pasta Grafiği bu konseptte **kaldırılıyor** (KPI şeridiyle bilgi tekrarı yaratıyordu).

**Kaldırılacak mevcut alanlar**: Sahte sparkline'lar, İş Emri Pasta Grafiği, tam genişlik Banka Şifreleri/Döviz Kurları kartları (küçültülüp taşınıyor).

**Birleştirilecek alanlar**: Açık Faturalar + Fatura Kuyruğu tek KPI'da (değer: açık fatura sayısı, alt metin: kuyrukta bekleyen sayısı) — iki ayrı kutu yerine bir kutu.

**Avantajları**: Operasyon ekibi/sahadaki personel için sabah açtığında "bugün ne yapmalıyım, nereye dikkat etmeliyim" sorusuna 5 saniyede cevap verir; finans/yönetim özetine ihtiyaç duymayan günlük kullanıcı için en hızlı ekran.

**Dezavantajları**: Üst yönetim için aylık/genel trend (müşteri sayısı, gelir büyüklüğü, geçen aya göre değişim) arka planda kalır — admin rolü için ikinci bir "yönetici görünümü"ne ihtiyaç doğurabilir.

**Metinsel wireframe (Web/Electron, ≥1200px)**:
```
┌───────────────────────────────────────────────────────────────────┐
│ Panel                                                    [Tema][Profil]│
├───────────────────────────────────────────────────────────────────┤
│ [Bugünkü İşler] [Açık İş Emirleri] [Devam Eden] [Süresi Dolanlar]  │  ← 4 KPI, tek satır
├───────────────────────────────────────────┬─────────────────────────┤
│ Dikkat Gerektirenler                       │ [Bugün Tahsilat][Bekleyen]│
│ • 3 lisans 30 gün içinde doluyor →         │ [Açık Faturalar]         │  ← 3 KPI
│ • Fatura kuyruğunda 5 kayıt →              │ Gelir (14 Gün) [küçük grafik]│
│                                             │                          │
│ Son Aktiviteler                            │                          │
│ • İş emri güncellendi — ACME  10 dk önce   │                          │
│ • Servis kaydı — Beta Ltd.    1 sa önce    │                          │
├───────────────────────────────────────────┴─────────────────────────┤
│ USD 34,12 • EUR 37,01 • GBP 43,22                     [ince şerit]  │
└───────────────────────────────────────────────────────────────────┘
```

**Metinsel wireframe (iOS)**:
```
┌───────────────────────┐
│ Panel        [🔔][👤] │
├───────────────────────┤
│ [Bugünkü İşler][Açık] │  ← 2x2
│ [Devam Eden][Süresi]  │
├───────────────────────┤
│ Dikkat Gerektirenler  │
│ • 3 lisans doluyor →  │
│ • 5 kuyruk kaydı →    │
├───────────────────────┤
│ [Bugün Tahsilat][Bekleyen]│ ← 2x2 (2. grup)
│ [Açık Faturalar]      │
├───────────────────────┤
│ Son Aktiviteler       │
│ • ACME — 10 dk önce   │
│ • Beta Ltd — 1 sa önce│
├───────────────────────┤
│ Gelir (14 Gün) ▁▂▃▅▆  │
└───────────────────────┘
```

---

### KONSEPT B — Yönetici Özeti

**Öncelik**: Gelir, Açık faturalar, Müşteri sayısı, İş emri durumu, Son 14 günlük eğilimler.

**Bölüm sıralaması**:
1. Üst KPI şeridi (4 kart) — Gelir (Bu Ay, revenueChangePercent ile), Açık Faturalar (totalInvoiceAmount alt metin), Toplam Müşteri, Bekleyen Tahsilat (totalReceivable).
2. Gelir (14 Gün) grafiği — büyük, birincil içerik (gerçek veri, mevcut haliyle korunuyor, sahte sparkline yok).
3. İş Emri Durumu — pasta yerine **yatay stacked bar** (Açık/Devam/Tamamlanan tek çubukta oranlı) + sayısal etiketler; pasta grafikten daha hızlı okunur, daha az yer kaplar.
4. Son Aktiviteler — kısaltılmış (yalnızca son 4-5), "Tümünü Gör" linkiyle ilgili modüle yönlendirme.
5. Döviz Kurları — kompakt şerit, sayfa altında.
6. Banka Şifreleri — üst bar hızlı erişim.

**Web yerleşimi**: Üstte 4'lü KPI şeridi tam genişlik. Altında 2 sütun: sol (flex 3) büyük Gelir grafiği + altında İş Emri stacked bar; sağ (flex 2) Son Aktiviteler (kısa liste).

**Electron yerleşimi**: Web ile aynı.

**iOS yerleşimi**: 4 KPI 2x2 grid → Gelir grafiği tam genişlik (kısaltılmış yükseklik) → İş Emri stacked bar tam genişlik → Son Aktiviteler (3 öğe + "Tümünü Gör"). Döviz/Banka Şifreleri yine bottom sheet'e taşınır.

**Kullanılacak KPI kartları**: Gelir (Bu Ay) + değişim yüzdesi, Açık Faturalar + tutar, Toplam Müşteri, Bekleyen Tahsilat.

**Kullanılacak grafikler**: Gelir (14 Gün) çizgi grafiği (birincil, büyütülmüş) + İş Emri Durumu stacked bar (pasta yerine).

**Kaldırılacak mevcut alanlar**: Sahte sparkline'lar, İş Emri Pasta Grafiği (bar ile değiştiriliyor), tam genişlik Banka Şifreleri/Döviz kartları.

**Birleştirilecek alanlar**: Açık İş Emirleri + Devam Eden + Tamamlanan tek stacked bar bileşeninde birleşiyor (3 ayrı KPI yerine 1 görsel + sayısal etiketler).

**Avantajları**: Bir yöneticinin sabah 1 dakikada "işletme nasıl gidiyor" sorusuna cevap alacağı, gelir ve trend ağırlıklı, temiz bir özet; az kart, yüksek bilgi yoğunluğu oranı.

**Dezavantajları**: Sahada günlük iş yürüten personel için "bugün ne yapmalıyım" sorusuna doğrudan cevap yok — Bugünkü İşler/Süresi Dolanlar gibi operasyonel acil bilgiler bu konseptte üstte değil, dolayısıyla operasyon ekibi için ikinci bir tık/ekran gerekebilir.

**Metinsel wireframe (Web/Electron)**:
```
┌───────────────────────────────────────────────────────────────────┐
│ Panel                                                    [Tema][Profil]│
├───────────────────────────────────────────────────────────────────┤
│ [Gelir ▲%12] [Açık Faturalar] [Toplam Müşteri] [Bekleyen Tahsilat] │
├─────────────────────────────────────────────┬───────────────────────┤
│ Gelir (Son 14 Gün)                           │ Son Aktiviteler       │
│ [büyük çizgi grafik]                         │ • ACME — 10 dk önce   │
│                                               │ • Beta Ltd — 1 sa önce│
│ İş Emri Durumu                               │ • ...                 │
│ [██████░░░░ Açık 6  Devam 3  Tamam 12]        │ Tümünü Gör →          │
├───────────────────────────────────────────────┴───────────────────────┤
│ USD 34,12 • EUR 37,01 • GBP 43,22                                    │
└───────────────────────────────────────────────────────────────────┘
```

**Metinsel wireframe (iOS)**:
```
┌───────────────────────┐
│ Panel        [🔔][👤] │
├───────────────────────┤
│ [Gelir ▲%12][Açık Fat]│  ← 2x2
│ [Müşteri][Bekleyen]   │
├───────────────────────┤
│ Gelir (14 Gün)        │
│ [çizgi grafik]        │
├───────────────────────┤
│ İş Emri Durumu        │
│ [██████░░░░]          │
│ Açık 6 · Devam 3 · Tamam 12│
├───────────────────────┤
│ Son Aktiviteler       │
│ • ACME — 10 dk önce   │
│ • Beta Ltd — 1 sa önce│
│ Tümünü Gör →          │
└───────────────────────┘
```

---

### KONSEPT C — Hibrit Dashboard (önerilen)

**Öncelik**: Operasyon ve finans dengeli; günlük kullanım kadar hızlı, yönetici özeti kadar bilgi yoğun.

**Bölüm sıralaması**:
1. Üst KPI şeridi (4 kart, sabit) — Bugünkü İşler, Açık İş Emirleri, Gelir (Bu Ay + değişim), Bekleyen Tahsilat. Bu 4 kart hem "bugün ne var" hem "genel nasıl gidiyor"u tek satırda dengeler.
2. İkinci KPI şeridi (3 kart, yalnızca ≥1080px'te aynı satırda 4'e tamamlanır gibi görünmesin diye ayrı grup, mobilde de görünür kalır) — Toplam Müşteri, Süresi Dolanlar, Açık Faturalar.
3. İki sütunlu içerik alanı: sol — Gelir (14 Gün) grafiği (orta boy) + İş Emri Durumu stacked bar; sağ — Son Aktiviteler.
4. Döviz Kurları — kompakt şerit, sayfa altında (Konsept A/B ile aynı).
5. Banka Şifreleri — üst bar hızlı erişim (Konsept A/B ile aynı).

**Web yerleşimi**: 1200px+'te üst 4'lü KPI şeridi + hemen altında ikinci 3'lü KPI şeridi (aynı görsel dilde, biraz daha küçük), ardından 2 sütun (sol flex 3: Gelir grafiği + stacked bar; sağ flex 2: Son Aktiviteler). 980-1199px arası KPI'lar 3'e, sonra 2'ye düşer (kural: masaüstünde satır başına en fazla 4).

**Electron yerleşimi**: Web ile aynı.

**iOS yerleşimi**: 1. şerit 2x2 grid, 2. şerit 2x2 grid (3 kart + 1 boş/hizalı boşluk ya da 3'lü tek satır kaydırmasız kompakt kart — kurala göre 2 sütun sabit, 3. kart alt satırda tek başına tam genişlik gösterilir), ardından Gelir grafiği (kısa), İş Emri stacked bar, Son Aktiviteler. Döviz/Banka Şifreleri bottom sheet'te.

**Kullanılacak KPI kartları** (7 toplam, iki gruba bölünmüş — Konsept A ile aynı toplam sayı ama farklı seçim/gruplama): Bugünkü İşler, Açık İş Emirleri, Gelir (Bu Ay), Bekleyen Tahsilat / Toplam Müşteri, Süresi Dolanlar, Açık Faturalar.

**Kullanılacak grafikler**: Gelir (14 Gün) çizgi grafiği (gerçek veri, orta boy) + İş Emri Durumu stacked bar (pasta yerine, Konsept B'deki gibi). Sahte sparkline yok.

**Kaldırılacak mevcut alanlar**: Sahte sparkline'lar, İş Emri Pasta Grafiği (bar'a dönüşüyor), tam genişlik Banka Şifreleri/Döviz kartları.

**Birleştirilecek alanlar**: Açık İş Emirleri + Devam Eden + Tamamlanan → stacked bar (Konsept B'deki gibi), ayrıca Açık Faturalar + Fatura Kuyruğu tek KPI'da birleşir (Konsept A'daki gibi).

**Avantajları**: Hem "bugün ne yapmalıyım" hem "işletme genel olarak nasıl" sorularına aynı ekranda, iki net şeritle cevap verir; A ve B'nin en güçlü yanlarını (operasyonel acil bilgi + finansal özet) tek ekranda dengeler; tüm roller (personel/admin) için aynı ekran anlamlı kalır, ikinci bir "yönetici görünümü" ihtiyacı doğmaz.

**Dezavantajları**: 7 KPI + 2 grafik + aktivite listesi, A veya B'nin tek başına olduğundan biraz daha fazla toplam öğe taşır (yine de bugünkü 13 karttan çok daha az); iki KPI şeridine bölünmüş olması ("bugün" ve "genel") ilk bakışta net değilse hafif bir bölüm başlığı/ayraç gerektirir (ör. ince "Bugün" / "Genel Bakış" etiketleri).

**Metinsel wireframe (Web/Electron, ≥1200px)**:
```
┌───────────────────────────────────────────────────────────────────┐
│ Panel                                                    [Tema][Profil]│
├───────────────────────────────────────────────────────────────────┤
│ Bugün                                                                │
│ [Bugünkü İşler] [Açık İş Emirleri] [Gelir ▲%12] [Bekleyen Tahsilat]│  ← 4 KPI
│ Genel Bakış                                                          │
│ [Toplam Müşteri] [Süresi Dolanlar] [Açık Faturalar]                 │  ← 3 KPI
├─────────────────────────────────────────────┬───────────────────────┤
│ Gelir (Son 14 Gün)                           │ Son Aktiviteler       │
│ [orta boy çizgi grafik]                      │ • ACME — 10 dk önce   │
│                                               │ • Beta Ltd — 1 sa önce│
│ İş Emri Durumu                               │ • ...                 │
│ [██████░░░░ Açık 6  Devam 3  Tamam 12]        │                       │
├───────────────────────────────────────────────┴───────────────────────┤
│ USD 34,12 • EUR 37,01 • GBP 43,22                                    │
└───────────────────────────────────────────────────────────────────┘
```

**Metinsel wireframe (iOS)**:
```
┌───────────────────────┐
│ Panel        [🔔][👤] │
├───────────────────────┤
│ Bugün                 │
│ [Bugünkü İşler][Açık] │  ← 2x2
│ [Gelir ▲%12][Bekleyen]│
├───────────────────────┤
│ Genel Bakış           │
│ [Müşteri][Süresi Dolan]│ ← 2x2 + 1 tam genişlik
│ [Açık Faturalar (tam)]│
├───────────────────────┤
│ Gelir (14 Gün)        │
│ [çizgi grafik, kısa]  │
├───────────────────────┤
│ İş Emri Durumu        │
│ [██████░░░░]          │
├───────────────────────┤
│ Son Aktiviteler       │
│ • ACME — 10 dk önce   │
│ • Beta Ltd — 1 sa önce│
└───────────────────────┘
```

---

## C. Öneri

**Konsept C (Hibrit) öneriliyor.** Gerekçe: Microvise CRM'de hem sahada günlük iş yürüten personel hem de genel durumu takip eden yöneticiler aynı `/panel` ekranını kullanıyor (rol bazlı görünürlük zaten `hasPageAccessProvider`/`hasActionAccessProvider` ile kodda mevcut). Konsept A yöneticiyi, Konsept B saha personelini ekrandan mahrum bırakıyor; Konsept C ikisini de "Bugün" ve "Genel Bakış" olarak net şekilde ayırıp tek ekranda karşılıyor ve bugünkü 13 kart/kart-benzeri yüzeyi 7 KPI + 2 grafik + 1 listeye indirerek görsel yoğunluğu da azaltıyor. Sahte sparkline'ların kaldırılması ve pasta grafiğin stacked bar'a dönüşmesi her üç konseptte ortak ama Konsept C'de bu değişikliklerin faydası en çok hissedilecek çünkü ekran zaten daha yoğun.

Onayınızı bekliyorum — onay olmadan hiçbir koda dokunmayacağım.
