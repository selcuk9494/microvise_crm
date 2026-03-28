alter table public.application_forms
add column if not exists is_active boolean not null default true;

alter table public.scrap_forms
add column if not exists is_active boolean not null default true;

alter table public.transfer_forms
add column if not exists is_active boolean not null default true;

create index if not exists idx_application_forms_is_active
on public.application_forms (is_active, created_at desc);

create index if not exists idx_scrap_forms_is_active
on public.scrap_forms (is_active, created_at desc);

create index if not exists idx_transfer_forms_is_active
on public.transfer_forms (is_active, created_at desc);
