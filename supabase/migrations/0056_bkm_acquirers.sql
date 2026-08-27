-- BKM AcquirerId (kullanıcı dilinde BKM ID) → banka adı tanımları
create table if not exists public.bkm_acquirers (
  id uuid primary key default gen_random_uuid(),
  bkm_id integer not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.bkm_acquirers (bkm_id, name) values
  (10, 'Ziraat Bankası'),
  (12, 'Halk Bankası'),
  (32, 'TEB'),
  (62, 'Garanti'),
  (64, 'İş Bankası'),
  (67, 'YKB'),
  (134, 'Denizbank')
on conflict (bkm_id) do nothing;

alter table public.bkm_acquirers enable row level security;

drop policy if exists bkm_acquirers_select on public.bkm_acquirers;
create policy bkm_acquirers_select
  on public.bkm_acquirers for select to authenticated using (true);

drop policy if exists bkm_acquirers_insert on public.bkm_acquirers;
create policy bkm_acquirers_insert
  on public.bkm_acquirers for insert to authenticated with check (true);

drop policy if exists bkm_acquirers_update on public.bkm_acquirers;
create policy bkm_acquirers_update
  on public.bkm_acquirers for update to authenticated using (true) with check (true);

drop policy if exists bkm_acquirers_delete on public.bkm_acquirers;
create policy bkm_acquirers_delete
  on public.bkm_acquirers for delete to authenticated using (true);
