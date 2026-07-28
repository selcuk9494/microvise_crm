alter table public.e_invoice_settings
  add column if not exists seller_bank_details text;

update public.e_invoice_settings
set seller_bank_details = concat_ws(
  E'\n',
  'Banka Hesap Bilgileri',
  'Türkiye İş Bankası',
  'Microvise Innovation Ltd',
  'TL IBAN: TR57 0006 4000 0016 8010 3409 94',
  'USD IBAN: TR41 0006 4000 0026 8010 4107 29'
)
where nullif(trim(seller_bank_details), '') is null;
