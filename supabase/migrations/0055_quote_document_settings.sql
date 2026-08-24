-- Teklif PDF: logo, banka bilgileri, özel şartlar (tek satır ayar kaydı)
create table if not exists public.quote_document_settings (
  id smallint primary key default 1 check (id = 1),
  logo_url text,
  company_title text not null default 'MICROVISE',
  company_subtitle text not null default 'Innovation Ltd',
  bank_details text,
  terms_and_conditions text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.quote_document_settings (id)
values (1)
on conflict (id) do nothing;

alter table public.quote_document_settings enable row level security;

drop policy if exists quote_document_settings_select on public.quote_document_settings;
create policy quote_document_settings_select
  on public.quote_document_settings for select to authenticated using (true);

drop policy if exists quote_document_settings_update on public.quote_document_settings;
create policy quote_document_settings_update
  on public.quote_document_settings for update to authenticated using (true) with check (true);
