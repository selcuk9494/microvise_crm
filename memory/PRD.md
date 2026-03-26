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

### Veritabanı Migration'ları
- 0001_init.sql - Temel tablolar
- 0002_crm_extensions.sql - CRM genişletmeleri
- 0003_billing_invoice_queue.sql - Faturalama kuyruğu
- 0004_payment_exchange_rate.sql - Ödeme kur kolonu
- 0005_erp_full_system.sql - Tam ERP sistemi

## Backlog (P0/P1/P2)

### P0 - Kritik
- [ ] PDF ekstre/fatura çıktısı
- [ ] E-posta gönderimi (Resend API gerekli)
- [ ] Excel export

### P1 - Önemli
- [ ] Servis modülü garanti takibi
- [ ] Servis parça ekleme
- [ ] Gelişmiş raporlar
- [ ] Dashboard istatistikleri

### P2 - Sonra
- [ ] Çek/Senet takibi
- [ ] Banka mutabakatı
- [ ] Çoklu şube desteği

## Teknik Notlar
- Supabase RLS aktif
- Kur API: Frankfurter (ücretsiz)
- E-posta: Supabase Edge Functions
- PDF: Henüz entegre edilmedi

## Sonraki Görevler
1. Migration'ları Supabase'de çalıştır
2. PDF/Excel export ekle
3. Resend API entegrasyonu
