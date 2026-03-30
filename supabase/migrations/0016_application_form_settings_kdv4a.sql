alter table public.application_form_settings
add column if not exists office_title_4a text not null default E'Maliye Bakanlığı\nGelir ve Vergi Dairesi Müdürlüğü\nLEFKOŞA';

alter table public.application_form_settings
add column if not exists kdv4a_title text not null default E'ÖDEME KAYDEDİCİ CİHAZ KULLANIM ONAYINA\nİLİŞKİN\nMALİ MÜHÜR UYGULAMA TUTANAĞI';

alter table public.application_form_settings
add column if not exists kdv4a_serial_number text not null default '';

alter table public.application_form_settings
add column if not exists kdv4a_seller_company_name text not null default 'MICROVISE INNOVATION LTD.';

alter table public.application_form_settings
add column if not exists kdv4a_seller_address text not null default 'Atatürk Cad Emek 2 No:1 Yenişehir Lefkoşa';

alter table public.application_form_settings
add column if not exists kdv4a_seller_tax_office_and_registry text not null default 'Lefkoşa Mş:19660';

alter table public.application_form_settings
add column if not exists kdv4a_seller_license_number text not null default '068';

alter table public.application_form_settings
add column if not exists kdv4a_warranty_period text not null default '12';

alter table public.application_form_settings
add column if not exists kdv4a_department_count text not null default '8';

alter table public.application_form_settings
add column if not exists kdv4a_service_company_name text not null default 'MICROVISE INNOVATION LTD.';

alter table public.application_form_settings
add column if not exists kdv4a_service_company_address text not null default 'Atatürk Cad Emek 2 No:1 Yenişehir Lefkoşa';

alter table public.application_form_settings
add column if not exists kdv4a_seal_applicant_name text not null default '';

alter table public.application_form_settings
add column if not exists kdv4a_seal_applicant_title text not null default '';

alter table public.application_form_settings
add column if not exists kdv4a_approval_document_date text not null default '';

alter table public.application_form_settings
add column if not exists kdv4a_approval_document_number text not null default '';

alter table public.application_form_settings
add column if not exists kdv4a_delivery_receiver_name text not null default 'Selçuk Yılmaz';

alter table public.application_form_settings
add column if not exists kdv4a_delivery_receiver_title text not null default 'Direktör';
