do $$
begin
  if to_regclass('public.invoice_items') is null then
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'invoice_items'
      and column_name = 'item_type'
  ) then
    begin
      alter table public.invoice_items drop constraint if exists invoice_items_item_type_check;
    exception when others then
      null;
    end;

    begin
      alter table public.invoice_items
        add constraint invoice_items_item_type_check
        check (item_type in ('line_renewal', 'gmp3_renewal', 'work_order_payment'));
    exception when others then
      null;
    end;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'invoice_items'
      and column_name = 'source_table'
  ) then
    begin
      alter table public.invoice_items drop constraint if exists invoice_items_source_table_check;
    exception when others then
      null;
    end;

    begin
      alter table public.invoice_items
        add constraint invoice_items_source_table_check
        check (source_table in ('lines', 'licenses', 'work_orders', 'payments'));
    exception when others then
      null;
    end;
  end if;
end $$;

