# İş Emirleri Fazı — Eleştiri ve Konseptler

Durum: Onay bekliyor. Hiçbir dosya değiştirilmedi.

Kapsam: `lib/features/work_orders/work_orders_list_screen.dart`, `work_orders_kanban_screen.dart`, `work_order_create_dialog.dart`, `work_order_detail_sheet.dart`, `work_order_region_colors.dart`. Business logic, provider'lar, `work_order_model.dart`, kapatma işlem mantığı (`_closeWorkOrder`, `work_order_close_sheet.dart`) **değişmeyecek** — bunlardaki tekrar (aşağıda §7'de not edildi) bilinçli olarak bu fazın dışında bırakıldı çünkü gerçek veri yazma mantığı içeriyor.

## A. Mevcut Durum — Eleştiri

### 1. Durum gösterimi: yedi farklı, birbiriyle çelişen kaynak
Aynı beş durum (`open`, `in_progress`, `approval_pending`, `done`, `cancelled`) için **yedi bağımsız** etiket/renk eşlemesi var: `_statusLabel` (filtre pili), `_compactStatusPill` (kart rozeti), `_statusBadge` (liste rozeti), `_statusColor` (tek paylaşılan renk kaynağı), kanban kartının kendi switch'i, kanban board'un 3 sabit kolonu, detay sayfasının header switch'i. Bunlar birbiriyle **çelişiyor**: `done` durumu liste rozetinde "TAMAMLANDI", kart pilinde "KAPALI", filtre pilinde "Kapalı" olarak üç farklı yazıyor. Daha ciddisi: kanban kartı, kanban board ve detay sayfası yalnızca open/in_progress/done'ı tanıyor — `approval_pending` ve `cancelled` durumundaki iş emirleri kanban board'da **hiç görünmüyor**, detay sayfasında "Bilinmiyor" rozetiyle gösteriliyor. Bu bir görsel tutarsızlık değil, kullanıcının bazı iş emirlerini bulamaması anlamına gelen gerçek bir kullanılabilirlik hatası.

### 2. Altı görünüm modu, dört bağımsız satır/kart bileşeni
İki dosyada toplam 6 render yolu var: reorderable grid, reorderable list, düz grid, düz liste, kanban board, mobil 3 sekmeli liste. Bunları 4 farklı, birbirinden habersiz widget besliyor (`_WorkOrderCard` liste ekranında, `_WorkOrderGridCard`, kanban'ın kendi `_WorkOrderCard`'ı — aynı isim, alakasız kod, `_WorkOrderListTile`). `preferGrid` mantığı `(kIsWeb && !isMobile) || isMobile` gibi okunması zor bir koşula dayanıyor. Bu kadar çok mod, kullanıcıya "hangi görünümdeyim, neden farklı görünüyor" sorusu sorduruyor ve her yeni alan eklemek 4 yerde ayrı güncelleme gerektiriyor.

### 3. Filtre çubuğu: dört farklı breakpoint, tek karta sıkıştırılmış üç görev
Filtre header'ı (arama, durum pili, tarih aralığı, "pasif göster", sıralama modu, istatistik rozetleri, toplu seçim) tek bir `AppCard` içine sıkıştırılmış ve 720/860/980/1100 gibi dört farklı, uygulamanın geri kalanında kullanılmayan (uygulama genelinde asıl yaygın ikincil kırılım 900'dür) breakpoint'e göre parçalanıyor. Mobilde bir kısmı inline kalıyor, bir kısmı bottom sheet'e taşınıyor — hangi kontrolün nerede olduğunu tahmin etmek zor.

### 4. Oluşturma diyaloğu: aynı iki bölüm üç kez yazılmış
"Operasyon Bilgileri" / "Planlama ve İletişim" bölümlemesi doğru bir fikir ama üç farklı genişlik diliminde (≥1100, 860-1100, <860) üç kez elle yeniden yazılmış. 12 alandan yalnızca 3'ünde doğrulama var; personel zorunluluğu gönderim *sonrası* SnackBar ile bildiriliyor (inline değil) — kullanıcı formu doldurup gönderene kadar eksik bilgiyi göremiyor.

### 5. Boş/yükleme/hata durumları: her ekranda farklı, `EmptyStateCard` hiç kullanılmıyor
Liste ekranında iki farklı boş durum (kayıt yok / filtreye uygun kayıt yok) iki ayrı ad hoc kart; kanban'da üçüncü ve dördüncü ad hoc boş metin (sütun başına, sekme başına). Yükleme durumu liste ekranında gerçek kart şekliyle uyuşmayan sahte bir iskelet çiziyor; kanban'da ise **masaüstünde bile mobil sekmeli görünümü** üç sahte iş emriyle gösteriyor — masaüstü kullanıcısı veri gelene kadar yanlış görünüm modunu görüyor. Hata metni liste ekranında ham `$error` içeriyor (teknik detay kullanıcıya sızıyor), kanban'da statik/anlamsız bir metin.

### 6. Bölge renkleri: legend'siz dekorasyon, ekranlar arası tutarsız
Şehir bazlı renk sistemi iyi düşünülmüş (sunucudan gelen tanımlarla + fallback hash-renk) ama yalnızca liste ekranının kart görünümlerinde kullanılıyor, kanban'da hiç yok, hiçbir yerde "bu renk hangi bölge" diye bir açıklama (legend) gösterilmiyor — kullanıcı için anlamı çözülemeyen bir renk kalabalığı.

### 7. (Kapsam dışı, yalnızca not) Kapatma işlemi iki ayrı yerde uygulanmış
`work_order_detail_sheet.dart` içindeki `_closeWorkOrder` ve ayrı `work_order_close_sheet.dart` aynı işi (ödeme/stok/fatura satırı/imza yazma) iki kez, bağımsız olarak yapıyor. Bu bir **business logic** tekrarıdır, bu fazın kapsamı dışındadır — dokunulmayacak, yalnızca teknik borç olarak kayda geçiyor.

## B. Konseptler

Ortak: tüm konseptlerde durum sistemi tek kaynağa (`status_tone` + iş emri durumlarına özel bir etiket sözlüğü) indirilir, boş/yükleme/hata durumları `EmptyStateCard`/`Skeletonizer`'a taşınır, breakpoint'ler uygulama genelindeki 900/1024 ölçeğine hizalanır. Hiçbiri kapatma işlem mantığına dokunmaz.

### KONSEPT A — Tek Liste, Akıllı Görünüm Anahtarı
Birincil yüzey tek bir yoğun liste (`AppDenseList` ailesi — bugün bu ekranda hiç kullanılmıyor, tam da bunun için var). Kanban, aynı veriyi aynı kart bileşeniyle gösteren **ikincil bir görünüm anahtarı** olur (liste/kanban toggle), reorder/grid modları kaldırılır. Filtre çubuğu tek bir `SmartFilterBar` çağrısına indirilir. Create dialog tek bir responsive iki-sütun/tek-sütun bölüm bileşenine (`DsFormSection`, design system'e eklenecek) oturtulur.
**Avantaj**: En az kod, en tutarlı, güçlü filtre/toplu işlem gücü korunuyor (admin/operasyon ekibi için ideal).
**Dezavantaj**: Kanban ikincil kaldığı için görsel akış/sürükle-bırak deneyimi öne çıkmıyor.

### KONSEPT B — Kanban-Öncelikli Operasyon Panosu
Jira/Trello tarzı, kanban board birincil ve varsayılan görünüm olur (5 durumun tamamı için kolon — bugünkü gibi sadece 3 değil). Liste, "Tablo Görünümü" adıyla ikincil, yoğun filtre/toplu-işlem gerektiren durumlar için sunulur. Tek bir kart bileşeni hem board hem tabloda kullanılır.
**Avantaj**: Görsel akış çok güçlü, durum değişimini sürükleyerek yapmak sahadaki iş takibini hızlandırır, "premium SaaS" hissi en yüksek bu konseptte.
**Dezavantaj**: Toplu seçim/atama gibi tablo-doğal işlemler board'da daha zahmetli; mobilde board deneyimi doğası gereği zayıflar (tab/liste'ye düşer).

### KONSEPT C — Hibrit: Varsayılan Tablo + Bir Tık Board (önerilecek)
Konsept A'nın yoğun/tutarlı listesini varsayılan yapar, Konsept B'nin tam 5 durumlu board'unu tek tıkla ulaşılan eşit-değerde ikinci sekme yapar (ikisi de aynı kart/satır bileşenini, aynı durum sistemini paylaşır). Toplu seçim/atama ve filtreler yalnızca tablo görünümünde anlamlı olduğu için orada kalır; board yalnızca hızlı durum değişimi + genel akış görünürlüğü sağlar.
**Avantaj**: Hem operasyon/admin ekibinin (filtre, toplu atama) hem sahadaki ekibin (hızlı durum takibi) ihtiyacını karşılar; tek kart bileşeni + tek durum sistemi sayesinde bakım maliyeti en düşük.
**Dezavantaj**: İki görünüm sürdürüleceği için Konsept A'dan biraz daha fazla iş yükü (yine de bugünkü 6 moddan çok daha az).

## C. Öneri
**Konsept C.** Gerekçe: Faz 0 denetimi ve bu fazın bulguları, asıl sorunun "kanban mı liste mi" değil, **aynı verinin 4 bağımsız bileşenle 6 kez yeniden çizilmesi** olduğunu gösteriyor. Tek kart/satır bileşeni + tek durum sistemi kurulduktan sonra board ve tabloyu ikisini de sunmak neredeyse ek maliyetsiz hale geliyor, ve bu tam olarak Jira Cloud'un yaptığı şey (aynı issue kartı hem board'da hem tabloda).

Onayınızı ve hangi konseptle ilerleyeceğinizi bekliyorum; onay olmadan hiçbir dosyaya dokunmayacağım.
