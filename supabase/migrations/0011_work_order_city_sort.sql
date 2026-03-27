alter table public.work_orders
  add column if not exists city text,
  add column if not exists sort_order integer not null default 0;

create index if not exists idx_work_orders_status_sort
on public.work_orders using btree (status, sort_order, created_at desc);
