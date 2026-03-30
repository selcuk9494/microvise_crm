create index if not exists idx_customers_active_city_name
on public.customers (is_active, city, name);

create index if not exists idx_customers_active_created_at
on public.customers (is_active, created_at);

create index if not exists idx_work_orders_active_status_sort
on public.work_orders (is_active, status, sort_order, created_at desc);

create index if not exists idx_payments_work_order_active_paid_at
on public.payments (work_order_id, is_active, paid_at desc);

create index if not exists idx_lines_customer_active
on public.lines (customer_id, is_active);

create index if not exists idx_licenses_customer_active_type
on public.licenses (customer_id, is_active, license_type);

create index if not exists idx_transactions_type_active_date
on public.transactions (transaction_type, is_active, transaction_date);

create index if not exists idx_invoices_active_status
on public.invoices (is_active, status);

create or replace view public.product_serial_inventory_summary
with (security_invoker = true) as
select
  product_id,
  count(*) filter (where is_active = true) as total_count,
  count(*) filter (where is_active = true and consumed_at is null) as available_count,
  count(*) filter (where is_active = true and consumed_at is not null) as consumed_count
from public.product_serial_inventory
group by product_id;

create or replace function public.dashboard_snapshot()
returns table (
  total_customers integer,
  open_work_orders integer,
  in_progress_work_orders integer,
  completed_work_orders integer,
  today_work_orders integer,
  expiring_soon integer,
  total_products integer,
  low_stock_products integer,
  revenue numeric,
  last_month_revenue numeric,
  today_collections numeric,
  total_receivable numeric,
  total_payable numeric,
  open_invoices integer,
  total_invoice_amount numeric
)
language sql
security invoker
set search_path = public
as $$
  with bounds as (
    select
      current_date as today,
      date_trunc('month', current_date)::date as current_month_start,
      (date_trunc('month', current_date) - interval '1 month')::date as last_month_start
  )
  select
    (select count(*)::integer from public.customers c where c.is_active = true) as total_customers,
    (select count(*)::integer from public.work_orders w where w.is_active = true and w.status = 'open') as open_work_orders,
    (select count(*)::integer from public.work_orders w where w.is_active = true and w.status = 'in_progress') as in_progress_work_orders,
    (select count(*)::integer from public.work_orders w where w.is_active = true and w.status = 'done') as completed_work_orders,
    (select count(*)::integer from public.work_orders w, bounds b where w.is_active = true and w.scheduled_date = b.today) as today_work_orders,
    (
      (select count(*)::integer from public.licenses l, bounds b
        where l.is_active = true
          and l.expires_at >= b.today
          and l.expires_at <= (b.today + interval '30 day')::date)
      +
      (select count(*)::integer from public.lines ln, bounds b
        where ln.is_active = true
          and ln.expires_at >= b.today
          and ln.expires_at <= (b.today + interval '30 day')::date)
    ) as expiring_soon,
    (select count(*)::integer from public.products p where p.is_active = true) as total_products,
    (select count(*)::integer from public.stock_levels s where coalesce(s.current_stock, 0) <= coalesce(s.min_stock, 0)) as low_stock_products,
    (select coalesce(sum(t.amount), 0) from public.transactions t, bounds b
      where t.transaction_type = 'collection'
        and t.is_active = true
        and t.transaction_date >= b.current_month_start) as revenue,
    (select coalesce(sum(t.amount), 0) from public.transactions t, bounds b
      where t.transaction_type = 'collection'
        and t.is_active = true
        and t.transaction_date >= b.last_month_start
        and t.transaction_date < b.current_month_start) as last_month_revenue,
    (select coalesce(sum(t.amount), 0) from public.transactions t, bounds b
      where t.transaction_type = 'collection'
        and t.is_active = true
        and t.transaction_date = b.today) as today_collections,
    (select coalesce(sum(case when a.balance > 0 then a.balance else 0 end), 0) from public.account_balances a) as total_receivable,
    (select coalesce(sum(case when a.balance < 0 then abs(a.balance) else 0 end), 0) from public.account_balances a) as total_payable,
    (select count(*)::integer from public.invoices i where i.is_active = true and i.status in ('open', 'partial')) as open_invoices,
    (select coalesce(sum(i.grand_total - coalesce(i.paid_amount, 0)), 0) from public.invoices i
      where i.is_active = true and i.status in ('open', 'partial')) as total_invoice_amount
  from bounds;
$$;
