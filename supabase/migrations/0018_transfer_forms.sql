create extension if not exists pgcrypto;

create table if not exists public.transfer_forms (
  id uuid primary key default gen_random_uuid(),
  row_number text,
  transferor_customer_id uuid references public.customers(id) on delete set null,
  transferor_name text not null,
  transferor_address text,
  transferor_tax_office_and_registry text,
  transferor_approval_date_no text,
  transferee_customer_id uuid references public.customers(id) on delete set null,
  transferee_name text not null,
  transferee_address text,
  transferee_tax_office_and_registry text,
  transferee_approval_date_no text,
  total_sales_receipt text,
  vat_collected text,
  last_receipt_date_no text,
  z_report_count text,
  other_device_info text,
  brand_model text,
  device_serial_no text,
  fiscal_symbol_company_code text,
  department_count text,
  transfer_date date not null default current_date,
  transfer_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.transfer_forms enable row level security;

drop policy if exists "transfer_forms_select" on public.transfer_forms;
create policy "transfer_forms_select"
on public.transfer_forms
for select
to authenticated
using (true);

drop policy if exists "transfer_forms_insert" on public.transfer_forms;
create policy "transfer_forms_insert"
on public.transfer_forms
for insert
to authenticated
with check (true);

drop policy if exists "transfer_forms_update" on public.transfer_forms;
create policy "transfer_forms_update"
on public.transfer_forms
for update
to authenticated
using (true)
with check (true);

drop policy if exists "transfer_forms_delete" on public.transfer_forms;
create policy "transfer_forms_delete"
on public.transfer_forms
for delete
to authenticated
using (public.is_admin());

create table if not exists public.transfer_form_settings (
  id text primary key default 'default',
  title text not null default E'KULLANILMIŞ ÖDEME KAYDEDİCİ CİHAZ\nDEVİR TUTANAĞI',
  subtitle text not null default '(Tebliğ No. 14, Madde 11 (1) )',
  office_title text not null default E'Ekonomi ve Maliye Bakanlığı\nGelir ve Vergi Dairesi Müdürlüğü,\nLefkoşa',
  row_number_label text not null default 'Sıra No.',
  transferor_section_title text not null default '1- CİHAZI DEVREDECEK OLANIN',
  transferor_name_label text not null default '- Adı - Soyadı / Ünvanı',
  transferor_address_label text not null default '- İşyeri Adresi',
  transferor_tax_label text not null default '- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No',
  transferor_approval_label text not null default '- Cihazın Kullanımı Onay Belgesi Tarih ve No'' su',
  transferee_section_title text not null default '2- CİHAZI DEVRALACAK OLANIN',
  transferee_name_label text not null default '- Adı - Soyadı / Ünvanı',
  transferee_address_label text not null default '- İşyeri Adresi',
  transferee_tax_label text not null default '- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No',
  transferee_approval_label text not null default '- Cihazın Kullanımı Onay Belgesi Tarih ve No'' su',
  device_summary_title text not null default '3- DEVREDENE AİT CİHAZDA BULUNAN BİLGİLER',
  total_sales_receipt_label text not null default '- Toplam Hasılat Tutarı',
  vat_collected_label text not null default '- Tahsil Edilen KDV Tutarı',
  last_receipt_date_no_label text not null default '- En son verilen fişin Tarih ve No'' su',
  z_report_count_label text not null default '- ''Z'' Raporu Sayısı',
  other_device_info_label text not null default '- Varsa Diğer Bilgiler',
  device_info_title text not null default '4- CİHAZA AİT BİLGİLER',
  brand_model_label text not null default '- Marka ve Modeli',
  device_serial_no_label text not null default '- Cihaz Sicil No',
  fiscal_symbol_company_code_label text not null default '- Mali Sembol ve Firma Kodu',
  department_count_label text not null default '- Cihazın Departman Sayısı',
  transfer_info_title text not null default '5- DEVİRE AİT BİLGİLER',
  transfer_date_label text not null default '- Devir Tarihi',
  transfer_reason_label text not null default '- Devir Nedeni',
  service_company_label text not null default '- Cihazın Bakım - Onarımını üstlenen yetkili firma',
  service_company_value text not null default 'Microvise Innovation Ltd.',
  statement_text text not null default 'Yukarıdaki bilgilerin tam ve doğru olduğunu beyan ederiz.',
  transferor_signature_title text not null default 'DEVREDENİN',
  transferee_signature_title text not null default 'DEVRALANIN',
  office_fill_title text not null default 'DAİRE TARAFINDAN DOLDURULACAKTIR',
  office_fill_text text not null default 'Yukarıdaki bilgiler tarafımdan / tarafımızdan kontrol edilmiş olup doğruluğu saptanmıştır.',
  controller_title text not null default 'KONTROLÜ YAPANIN / YAPANLARIN',
  controller_date_label text not null default 'Tarih',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.transfer_form_settings enable row level security;

drop policy if exists "transfer_form_settings_select" on public.transfer_form_settings;
create policy "transfer_form_settings_select"
on public.transfer_form_settings
for select
to authenticated
using (true);

drop policy if exists "transfer_form_settings_upsert" on public.transfer_form_settings;
create policy "transfer_form_settings_upsert"
on public.transfer_form_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());
