create extension if not exists pgcrypto;

create table if not exists public.scrap_forms (
  id uuid primary key default gen_random_uuid(),
  form_date date not null default current_date,
  row_number text,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text not null,
  customer_address text,
  customer_tax_office_and_number text,
  device_brand_model_registry text,
  okc_start_date date,
  last_used_date date,
  z_report_count text,
  total_vat_collection text,
  total_collection text,
  intervention_purpose text,
  other_findings text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.scrap_forms enable row level security;

drop policy if exists "scrap_forms_select" on public.scrap_forms;
create policy "scrap_forms_select"
on public.scrap_forms
for select
to authenticated
using (true);

drop policy if exists "scrap_forms_insert" on public.scrap_forms;
create policy "scrap_forms_insert"
on public.scrap_forms
for insert
to authenticated
with check (true);

drop policy if exists "scrap_forms_update" on public.scrap_forms;
create policy "scrap_forms_update"
on public.scrap_forms
for update
to authenticated
using (true)
with check (true);

drop policy if exists "scrap_forms_delete" on public.scrap_forms;
create policy "scrap_forms_delete"
on public.scrap_forms
for delete
to authenticated
using (public.is_admin());

create table if not exists public.scrap_form_settings (
  id text primary key default 'default',
  form_code text not null default '(Forma. KDV 15 b)',
  title text not null default E'HURDAYA AYRILAN\nÖDEME KAYDEDİCİ CİHAZLARA AİT\nTUTANAK',
  date_label text not null default 'TARİH',
  row_number_label text not null default 'SIRA NO',
  service_section_title text not null default '1- YETKİLİ SERVİSİN',
  service_company_label text not null default '- Servisliğini Yaptığı Firma',
  service_identity_label text not null default '- Adı, Soyadı veya Ünvanı ve Sicil No',
  service_address_label text not null default '- Adresi',
  service_tax_label text not null default '- Vergi Dairesi ve Numarası',
  service_company_value text not null default 'Ingenico',
  service_identity_value text not null default 'Microvise Innovation Ltd',
  service_address_value text not null default 'Atatürk Cad Emek 2 No:1 Yenişehir',
  service_tax_value text not null default '19660',
  owner_section_title text not null default '2- CİHAZIN SAHİBİ MÜKELLEFİN',
  owner_name_label text not null default '- Adı, Soyadı veya Ünvanı',
  owner_address_label text not null default '- Adresi',
  owner_tax_label text not null default '- Vergi Dairesi ve Numarası',
  device_section_title text not null default '3- CİHAZIN MARKA MODEL VE SİCİL NO',
  start_date_label text not null default '4- CİHAZIN KULLANILMAYA BAŞLANDIĞI TARİH',
  last_used_date_label text not null default '5- CİHAZIN EN SON KULLANILDIĞI TARİH',
  summary_title text not null default '6- CİHAZIN SON KULLANIM TARİHİ İTİBARİYLE',
  z_report_label text not null default '- Z'' Rapor Sayısı',
  vat_total_label text not null default '- Toplam Katma Değer Vergisi Tahsilatı',
  gross_total_label text not null default '- Toplam Hasılat',
  purpose_label text not null default '7- MÜDAHALENİN AMACI',
  other_findings_label text not null default '8- VARSA DİĞER TESPİTLER',
  owner_signature_title text not null default E'CİHAZ SAHİBİ MÜKELLEFİN\nİMZASI',
  service_signature_title text not null default E'YETKİLİ SERVİS ELEMANININ\nİMZASI',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.scrap_form_settings enable row level security;

drop policy if exists "scrap_form_settings_select" on public.scrap_form_settings;
create policy "scrap_form_settings_select"
on public.scrap_form_settings
for select
to authenticated
using (true);

drop policy if exists "scrap_form_settings_upsert" on public.scrap_form_settings;
create policy "scrap_form_settings_upsert"
on public.scrap_form_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());
