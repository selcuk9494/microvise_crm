alter table public.hat_lisans_billing_settings
  add column if not exists line_payment_title text,
  add column if not exists gmp3_payment_title text,
  add column if not exists iresto_payment_title text;

update public.hat_lisans_billing_settings
set
  line_payment_title = coalesce(nullif(btrim(line_payment_title), ''), 'Yazar kasa İnternet hattı Yıllık kullanım'),
  gmp3_payment_title = coalesce(nullif(btrim(gmp3_payment_title), ''), 'Yazar Kasa Entegrasyon ödemesi'),
  iresto_payment_title = coalesce(nullif(btrim(iresto_payment_title), ''), 'iResto Yazarkasa Entegrasyon ödemesi')
where id = 1;
