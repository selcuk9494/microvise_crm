# Microvise CRM - ERP Sistemi PRD

## Proje Özeti
Flutter + Supabase tabanlı kapsamlı CRM ve ERP sistemi.

## Kullanıcı Personaları
- **Admin**: Tüm yetkiler, raporlama, kullanıcı yönetimi
- **Personel**: İş emirleri, servis, müşteri yönetimi

## Temel Gereksinimler (Statik)
- Müşteri/Cari Yönetimi
- İş Emirleri (Açık/Devam/Kapalı)
- Servis Takip Sistemi
- Fatura Yönetimi (Alış/Satış)
- Ödeme/Tahsilat Takibi
- Stok Yönetimi
- Raporlama
- Hat/Lisans Takibi

## Uygulanan Özellikler

### Sprint 1 - Ocak 2026
- [x] İş Emirleri liste ekranı (Kanban yerine)
- [x] Üst menüde Açık/Devam Ediyor/Kapalı filtreleri
- [x] İş emri detay sheet (tıklayınca açılır)
- [x] Parçalı ödeme sistemi (TL, USD, EUR, GBP)
- [x] Otomatik kur çekimi (Frankfurter API)
- [x] Müşteri dijital imza
- [x] İmza ile e-posta gönderimi

### Sprint 2 - Ocak 2026
- [x] Faturalar modülü (Alış/Satış)
- [x] Otomatik fatura numaralama
- [x] Fatura kalemleri yönetimi
- [x] Çoklu para birimi desteği
- [x] Fatura ödeme/tahsilat
- [x] Cari hesaplar ekranı
- [x] Cari bakiye görüntüleme
- [x] Açık fatura ekstresi
- [x] Fatura seçerek ekstre
- [x] Ürün/Hizmet kataloğu
- [x] Stok takip sistemi
- [x] Stok düzeltme
- [x] Kritik stok uyarıları

### Sprint 3 - Aralık 2025
- [x] Hat & Lisans takip ekranı (subscriptions_screen.dart)
- [x] Hat/Lisans süre dolum uyarıları
- [x] Router ve sidebar'a Hat/Lisans entegrasyonu
- [x] İş Emri Tipleri tanımlamaları (definitions_screen.dart)
- [x] KDV Oranları tanımlamaları
- [x] Renk seçimli iş emri tipi ekleme
- [x] Toplu müşteri Excel import özelliği
- [x] Excel dosya parse ve preview
- [x] Dashboard geliştirilmiş istatistikler (8 metrik kartı)
- [x] İş emri durumu pie chart grafiği
- [x] Gelir değişim yüzdesi gösterimi
- [x] Müşteri Excel export özelliği

### Veritabanı Migration'ları
- 0001_init.sql - Temel tablolar
- 0002_crm_extensions.sql - CRM genişletmeleri
- 0003_billing_invoice_queue.sql - Faturalama kuyruğu
- 0004_payment_exchange_rate.sql - Ödeme kur kolonu
- 0005_erp_full_system.sql - Tam ERP sistemi
- 0006_definitions_tables.sql - İş emri tipleri, KDV oranları

## Backlog (P0/P1/P2)

### P0 - Kritik
- [ ] PDF ekstre/fatura çıktısı
- [ ] E-posta gönderimi (Resend API gerekli)

### P1 - Önemli
- [ ] Servis modülü garanti takibi
- [ ] Servis parça ekleme
- [ ] Gelişmiş raporlar
- [ ] Work Orders liste debug (status string eşleşmesi kontrol edilecek)

### P2 - Sonra
- [ ] Çek/Senet takibi
- [ ] Banka mutabakatı
- [ ] Çoklu şube desteği

## Teknik Notlar
- Supabase RLS aktif
- Kur API: Frankfurter (ücretsiz)
- E-posta: Supabase Edge Functions
- PDF: Henüz entegre edilmedi
- Excel Import: file_picker + excel paketi

## Bilinen Sorunlar
- Work Orders listesi boş görünme sorunu: Sayaçlar doğru değer gösteriyor ama liste boş. Status string eşleşmesi veya RLS politikası kontrol edilmeli. Debug print'ler tarayıcı konsolunda görünecek.

## Sonraki Görevler
1. Vercel'e deploy et ve Work Orders sorununu debug et
2. PDF/Excel export ekle
3. Resend API entegrasyonu
