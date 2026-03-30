alter table public.users
  add column if not exists email text,
  add column if not exists page_permissions text[] not null default '{}'::text[];

update public.users as u
set email = au.email
from auth.users as au
where au.id = u.id
  and coalesce(u.email, '') = '';

update public.users
set page_permissions = array[
  'panel',
  'musteriler',
  'formlar',
  'is_emirleri',
  'servis',
  'raporlar',
  'urunler',
  'faturalama'
]::text[]
where role = 'personel'
  and (
    page_permissions is null
    or coalesce(array_length(page_permissions, 1), 0) = 0
  );

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, full_name, role, email, page_permissions)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    'personel',
    new.email,
    array[
      'panel',
      'musteriler',
      'formlar',
      'is_emirleri',
      'servis',
      'raporlar',
      'urunler',
      'faturalama'
    ]::text[]
  )
  on conflict (id) do update
    set email = excluded.email;
  return new;
end;
$$;
