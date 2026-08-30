create table if not exists public.hat_lisans_prior_collections (
  customer_id uuid primary key references public.customers(id) on delete cascade,
  collected_at timestamptz not null default now(),
  collected_by uuid,
  note text
);
