-- Ödeme tablosuna exchange_rate kolonu ekleme
alter table public.payments
  add column if not exists exchange_rate numeric(10,4) default 1.0;

-- GBP currency desteği için check constraint güncelleme (eğer varsa)
-- Mevcut currency check constraint yoksa sorun yok
