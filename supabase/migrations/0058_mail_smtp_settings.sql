-- Fatura / ödeme linki mailleri için SMTP ayarları (E-Fatura > Ayarlar)
alter table public.e_invoice_settings
  add column if not exists smtp_host text,
  add column if not exists smtp_port text default '587',
  add column if not exists smtp_secure text default 'false',
  add column if not exists smtp_user text,
  add column if not exists smtp_pass text,
  add column if not exists smtp_from text;

update public.e_invoice_settings
set
  smtp_host = coalesce(nullif(btrim(smtp_host), ''), 'smtp.gmail.com'),
  smtp_port = coalesce(nullif(btrim(smtp_port), ''), '587'),
  smtp_secure = coalesce(nullif(btrim(smtp_secure), ''), 'false'),
  smtp_user = coalesce(nullif(btrim(smtp_user), ''), 'microvisefood@gmail.com'),
  smtp_from = coalesce(
    nullif(btrim(smtp_from), ''),
    'Microvise Innovation <microvisefood@gmail.com>'
  )
where is_active = true;
