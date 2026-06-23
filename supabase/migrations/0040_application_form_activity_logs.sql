create table if not exists public.application_form_activity_logs (
  id uuid primary key default gen_random_uuid(),
  application_form_id uuid not null,
  action text not null,
  actor_id uuid,
  actor_name text,
  changes jsonb not null default '[]'::jsonb,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_application_form_activity_logs_form_created
on public.application_form_activity_logs (application_form_id, created_at desc);

