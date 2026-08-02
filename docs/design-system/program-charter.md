# Microvise CRM — Premium SaaS Dönüşüm Programı (Tüzük)

Bu doküman, Dashboard fazından sonra tüm uygulamaya uygulanacak standart süreci ve kuralları tek yerde toplar. Her yeni ekran fazına başlarken bu dosyaya bakılır.

## Kalite hedefi
Microsoft 365 Admin Center, Linear, Stripe Dashboard, Notion, ClickUp, Atlassian Jira Cloud seviyesinde profesyonel SaaS deneyimi. Amaç "güzelleştirme" değil, satılabilir kurumsal ürün kalitesi.

## Sabit kurallar (her ekran için geçerli)
- Business logic, API, Riverpod provider, repository katmanı, veritabanı modeli değişmez. Yalnızca UI/UX katmanı.
- Navigasyon yapısı (router, route'lar) bozulmaz.
- Tek Design System: Light / Dark / Auto (`themeModeProvider` — mevcut, dokunulmuyor). Hiçbir ekran bu üç temanın dışına çıkmaz.
- Tüm ekranlar aynı dili konuşur: aynı spacing (`ds_tokens`), aynı tipografi (Inter/AppTheme textTheme), aynı ikon ailesi (`Icons.*_rounded` birincil), aynı buton/kart/filtre çubuğu/tablo/dialog/form/empty-state/skeleton/hata ekranı kalıpları.
- Yeni bileşen gerekiyorsa önce `lib/design_system/` içine eklenir (kanonikleştirilir), ekrana özel tek kullanımlık widget yazılmaz. Var olan `lib/core/ui/*` bileşenleri (AppCard, AppSectionCard, AppBadge, EmptyStateCard, SmartFilterBar, CompactStatCard, AppDenseList) öncelikle değerlendirilir; gerçekten eksikse `design_system` genişletilir.
- Tekrar eden widget'lar ortaklaştırılır, gereksiz yeni widget yazılmaz.
- Her ekran için süreç: **(1) mevcut UX eleştirisi → (2) en az 3 konsept → (3) onay → (4) uygulama → (5) format/analyze (mümkünse build) → (6) rapor.** Onay alınmadan hiçbir ekran koda dokunulmaz.
- Rapor içeriği: değiştirilen dosyalar, UX iyileştirmeleri, yeni component'ler, kalan teknik borç.

## Platform kapsamı (netleşti)
- **Web + Electron**: tek kod tabanı, Electron yalnızca Flutter Web derlemesini sarmalıyor (native masaüstü runner yok) — bu yeterli, native macOS/Windows Flutter hedefi eklenmeyecek.
- **iOS, Android**: mevcut native hedefler, responsive kırılım noktalarıyla telefon/tablet (iPad, Android Tablet) yoğunluğu ayarlanacak — ayrı bir build hedefi değil, aynı hedefin responsive davranışı.
- Bilgi mimarisi tüm platformlarda aynı kalır; yalnızca yerleşim/yoğunluk platforma göre uyarlanır.

## Ekran haritası ve durum

| # | Ekran (kullanıcı adı) | Proje karşılığı | Durum |
|---|---|---|---|
| 0 | Dashboard | `dashboard_screen.dart` | ✅ Konsept C uygulandı, statik inceleme geçti |
| 1 | İş Emirleri | `work_orders_list_screen.dart`, `work_orders_kanban_screen.dart` | 🔜 Sırada |
| 2 | Müşteriler | `customers_screen.dart`, `customer_detail_screen.dart` | Bekliyor |
| 3 | Servis | `service_screen.dart`, `service_detail_screen.dart` | Bekliyor |
| 4 | Personel | `personnel_screen.dart` | Bekliyor |
| 5 | Tanımlamalar | `definitions_screen.dart` | Bekliyor |
| 6 | Stok | `stock_screen.dart` | Bekliyor |
| 7 | Satın Alma | **Yok** — projede karşılığı bulunamadı | ⚠️ Netleştirilmeli |
| 8 | Faturalar | `invoices_screen.dart`, `billing_screen.dart` | Bekliyor |
| 9 | Cari Hesaplar | `invoices/accounts_screen.dart` (en yakın eşleşme) | Bekliyor — isim teyidi gerekebilir |
| 10 | Tahsilatlar | `work_orders/work_order_payments_screen.dart` (en yakın eşleşme) | Bekliyor — isim teyidi gerekebilir |
| 11 | Takvim | **Yok** | ⚠️ Netleştirilmeli |
| 12 | Görevler | **Yok** | ⚠️ Netleştirilmeli |
| 13 | Bildirimler | **Yok** (üst bar'da işlevsiz bir zil ikonu var, `onPressed: () {}`) | ⚠️ Netleştirilmeli |
| 14 | Raporlar | `reports_screen.dart` | Bekliyor |
| 15 | Ayarlar | **Yok** (profil menüsünde işlevsiz bir "Ayarlar" öğesi var) | ⚠️ Netleştirilmeli, ama mevcut provider'larla (tema, profil, çıkış) kısmen UI-only yapılabilir |

**Açık nokta**: Satın Alma, Takvim, Görevler, Bildirimler gerçekten yeni modüller — yeni veri modeli/provider/API gerektirir, bu da "business logic'e dokunma" kuralıyla doğrudan çelişir. Kullanıcı bunların "sıfırdan oluşturulmasını" istedi; bu ekranların sırası geldiğinde ayrı bir kapsam/veri modeli konuşması yapılacak (bu tasarım-katmanı programının dışında, ayrı bir özellik geliştirme kapsamı). Ayarlar kısmen istisna — sadece mevcut provider'ları (tema modu, kullanıcı profili, çıkış) yüzeye çıkaran bir ekran ise yeni backend gerekmeyebilir.

## Sıradaki adım
İş Emirleri — eleştiri ve 3 konsept (uygulama değil).
