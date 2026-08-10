alter table public.scrap_form_settings
alter column service_tax_value set default 'Lefkoşa VKN 620009058';

update public.scrap_form_settings
set
  service_tax_value = 'Lefkoşa VKN 620009058',
  updated_at = now()
where service_tax_value = '19660';
