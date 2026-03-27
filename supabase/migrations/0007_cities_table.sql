create table if not exists public.cities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists cities_name_idx on public.cities (name);
