create table if not exists public.application_form_settings (
  id text primary key,
  office_title text not null,
  intro_text text not null,
  optional_power_precaution_text text not null default 'Opsiyonel',
  manual_included_text text not null default 'Var',
  service_company_name text not null,
  service_company_address text not null,
  applicant_status text not null default 'DİREKTÖR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.application_form_settings (
  id,
  office_title,
  intro_text,
  optional_power_precaution_text,
  manual_included_text,
  service_company_name,
  service_company_address,
  applicant_status
)
values (
  'default',
  'Maliye Bakanlığı
Gelir ve Vergi Dairesi
LEFKOŞA',
  '47/1992 Sayılı Katma Değer Vergisi Yazası'' nın 53'' üncü maddesi uyarınca işletmemizin Ödeme Kaydedici Cihaz kullanma zorunluluğunun yerine getirilebilmesi için aşağıdaki hususları beyan eder, gerekli onayın verilmesini rica ederim.',
  'Opsiyonel',
  'Var',
  'MICROVISE INNOVATION LTD.',
  'Atatürk Cad Emek 2 No:1 Yenişehir Lefkoşa',
  'DİREKTÖR'
)
on conflict (id) do nothing;

alter table public.application_form_settings enable row level security;

drop policy if exists "application_form_settings_select" on public.application_form_settings;
create policy "application_form_settings_select"
on public.application_form_settings
for select
to authenticated
using (true);

drop policy if exists "application_form_settings_update" on public.application_form_settings;
create policy "application_form_settings_update"
on public.application_form_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.application_form_settings_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_application_form_settings_updated_at on public.application_form_settings;
create trigger set_application_form_settings_updated_at
before update on public.application_form_settings
for each row
execute function public.application_form_settings_set_updated_at();
