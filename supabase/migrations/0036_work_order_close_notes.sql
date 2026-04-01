create table if not exists public.work_order_close_notes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  sort_order integer default 0,
  created_at timestamptz not null default now()
);

insert into public.work_order_close_notes (name, sort_order) values
  ('Kurulum tamamlandı', 1),
  ('Arıza giderildi', 2),
  ('Bakım yapıldı', 3),
  ('Müşteri yerinde yok', 4),
  ('Erişim sağlanamadı', 5)
on conflict (name) do nothing;
