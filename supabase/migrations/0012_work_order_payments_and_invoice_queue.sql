alter table public.invoice_items
  alter column invoice_id drop not null;

alter table public.payments
  add column if not exists payment_method text default 'cash';

do $$
declare
  constraint_name text;
begin
  select conname
    into constraint_name
  from pg_constraint
  where conrelid = 'public.transactions'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%payment_method%';

  if constraint_name is not null then
    execute format(
      'alter table public.transactions drop constraint %I',
      constraint_name
    );
  end if;
end $$;

alter table public.transactions
  alter column payment_method set default 'cash';

alter table public.transactions
  add constraint transactions_payment_method_check
  check (payment_method in ('cash', 'bank', 'credit_card', 'check', 'pos', 'other'));
