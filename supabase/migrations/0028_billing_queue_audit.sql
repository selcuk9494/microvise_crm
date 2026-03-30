alter table public.invoice_items
  add column if not exists is_active boolean not null default true,
  add column if not exists source_event text,
  add column if not exists source_label text,
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists updated_at timestamptz,
  add column if not exists deactivated_by uuid references auth.users(id),
  add column if not exists deactivated_at timestamptz;

create index if not exists idx_invoice_items_active_status
on public.invoice_items (is_active, status, created_at desc);

do $$
declare
  item_constraint text;
  source_constraint text;
begin
  select conname
    into item_constraint
  from pg_constraint
  where conrelid = 'public.invoice_items'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%item_type%';

  if item_constraint is not null then
    execute format(
      'alter table public.invoice_items drop constraint %I',
      item_constraint
    );
  end if;

  select conname
    into source_constraint
  from pg_constraint
  where conrelid = 'public.invoice_items'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%source_table%';

  if source_constraint is not null then
    execute format(
      'alter table public.invoice_items drop constraint %I',
      source_constraint
    );
  end if;
end $$;
