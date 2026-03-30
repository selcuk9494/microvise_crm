-- =====================================================
-- ERP FULL SYSTEM MIGRATION
-- Cari Hesaplar, Faturalar, Stok, Servis Modülü
-- =====================================================

-- 1. CARİ HESAPLAR (Müşteri + Tedarikçi)
-- customers tablosunu genişlet
alter table public.customers
  add column if not exists tax_number text,
  add column if not exists tax_office text,
  add column if not exists email text,
  add column if not exists phone1 text,
  add column if not exists phone2 text,
  add column if not exists address text,
  add column if not exists account_type text default 'customer' check (account_type in ('customer', 'supplier', 'both')),
  add column if not exists opening_balance numeric(14,2) default 0,
  add column if not exists currency text default 'TRY' check (currency in ('TRY', 'USD', 'EUR', 'GBP'));

-- 2. FATURA NUMARALAMA AYARLARI
create table if not exists public.invoice_settings (
  id uuid primary key default gen_random_uuid(),
  invoice_type text not null check (invoice_type in ('purchase', 'sales')),
  prefix text not null default '',
  next_number integer not null default 1,
  year integer not null default extract(year from current_date),
  created_at timestamptz not null default now(),
  unique(invoice_type, year)
);

-- Default ayarlar
insert into public.invoice_settings (invoice_type, prefix, next_number, year)
values 
  ('purchase', 'ALŞ', 1, extract(year from current_date)),
  ('sales', 'STŞ', 1, extract(year from current_date))
on conflict (invoice_type, year) do nothing;

-- 3. FATURALAR TABLOSU
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  invoice_type text not null check (invoice_type in ('purchase', 'sales')),
  customer_id uuid not null references public.customers (id) on delete restrict,
  invoice_date date not null default current_date,
  due_date date,
  currency text not null default 'TRY' check (currency in ('TRY', 'USD', 'EUR', 'GBP')),
  exchange_rate numeric(10,4) default 1.0,
  subtotal numeric(14,2) not null default 0,
  tax_total numeric(14,2) not null default 0,
  discount_total numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  paid_amount numeric(14,2) not null default 0,
  status text not null default 'open' check (status in ('draft', 'open', 'partial', 'paid', 'cancelled')),
  notes text,
  service_record_id uuid references public.service_records (id) on delete set null,
  work_order_id uuid references public.work_orders (id) on delete set null,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 4. FATURA KALEMLERİ
create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  description text not null,
  quantity numeric(12,4) not null default 1,
  unit text default 'Adet',
  unit_price numeric(14,4) not null default 0,
  tax_rate numeric(5,2) not null default 20,
  tax_amount numeric(14,2) not null default 0,
  discount_rate numeric(5,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,
  sort_order integer default 0,
  created_at timestamptz not null default now()
);

-- 5. ÜRÜN/HİZMET KATALOĞU
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  description text,
  category text,
  product_type text not null default 'product' check (product_type in ('product', 'service', 'part')),
  unit text default 'Adet',
  purchase_price numeric(14,4) default 0,
  sale_price numeric(14,4) default 0,
  tax_rate numeric(5,2) default 20,
  currency text default 'TRY',
  track_stock boolean default false,
  min_stock numeric(12,4) default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

-- 6. STOK HAREKETLERİ
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  movement_type text not null check (movement_type in ('in', 'out', 'adjustment')),
  quantity numeric(12,4) not null,
  reference_type text, -- 'invoice', 'service', 'adjustment'
  reference_id uuid,
  unit_cost numeric(14,4),
  notes text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

-- 7. STOK DURUMU (View)
create or replace view public.stock_levels as
select 
  p.id as product_id,
  p.code,
  p.name,
  p.category,
  p.min_stock,
  coalesce(sum(case when sm.movement_type = 'in' then sm.quantity else 0 end), 0) -
  coalesce(sum(case when sm.movement_type = 'out' then sm.quantity else 0 end), 0) +
  coalesce(sum(case when sm.movement_type = 'adjustment' then sm.quantity else 0 end), 0) as current_stock
from public.products p
left join public.stock_movements sm on sm.product_id = p.id
where p.track_stock = true and p.is_active = true
group by p.id, p.code, p.name, p.category, p.min_stock;

-- 8. TAHSİLAT / ÖDEME HAREKETLERİ
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete restrict,
  transaction_type text not null check (transaction_type in ('collection', 'payment')), -- tahsilat / ödeme
  amount numeric(14,2) not null,
  currency text not null default 'TRY',
  exchange_rate numeric(10,4) default 1.0,
  payment_method text default 'cash' check (payment_method in ('cash', 'bank', 'credit_card', 'check', 'other')),
  transaction_date date not null default current_date,
  invoice_id uuid references public.invoices (id) on delete set null,
  description text,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

-- 9. SERVİS KAYITLARI GENİŞLETME
alter table public.service_records
  add column if not exists device_brand text,
  add column if not exists device_model text,
  add column if not exists device_serial text,
  add column if not exists fault_description text,
  add column if not exists diagnosis text,
  add column if not exists repair_notes text,
  add column if not exists warranty_status text default 'none' check (warranty_status in ('none', 'in_warranty', 'out_warranty')),
  add column if not exists warranty_end_date date,
  add column if not exists estimated_cost numeric(14,2),
  add column if not exists labor_cost numeric(14,2) default 0,
  add column if not exists parts_cost numeric(14,2) default 0,
  add column if not exists received_date date default current_date,
  add column if not exists completed_date date,
  add column if not exists delivered_date date,
  add column if not exists priority text default 'normal' check (priority in ('low', 'normal', 'high', 'urgent'));

-- 10. SERVİS PARÇALARI
create table if not exists public.service_parts (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.service_records (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  description text not null,
  quantity numeric(12,4) not null default 1,
  unit_price numeric(14,4) not null default 0,
  total_price numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

-- 11. CARİ HESAP BAKIYE GÖRÜNÜMÜ
create or replace view public.account_balances as
select 
  c.id as customer_id,
  c.name,
  c.account_type,
  c.currency,
  c.opening_balance,
  -- Satış faturaları (alacak)
  coalesce(sum(case when i.invoice_type = 'sales' and i.status != 'cancelled' then i.grand_total else 0 end), 0) as sales_total,
  -- Alış faturaları (borç)
  coalesce(sum(case when i.invoice_type = 'purchase' and i.status != 'cancelled' then i.grand_total else 0 end), 0) as purchase_total,
  -- Tahsilatlar
  coalesce((select sum(t.amount) from public.transactions t where t.customer_id = c.id and t.transaction_type = 'collection' and t.is_active = true), 0) as collections_total,
  -- Ödemeler
  coalesce((select sum(t.amount) from public.transactions t where t.customer_id = c.id and t.transaction_type = 'payment' and t.is_active = true), 0) as payments_total,
  -- Net Bakiye (Alacak - Tahsilat + Borç - Ödeme + Açılış)
  c.opening_balance +
  coalesce(sum(case when i.invoice_type = 'sales' and i.status != 'cancelled' then i.grand_total else 0 end), 0) -
  coalesce((select sum(t.amount) from public.transactions t where t.customer_id = c.id and t.transaction_type = 'collection' and t.is_active = true), 0) -
  coalesce(sum(case when i.invoice_type = 'purchase' and i.status != 'cancelled' then i.grand_total else 0 end), 0) +
  coalesce((select sum(t.amount) from public.transactions t where t.customer_id = c.id and t.transaction_type = 'payment' and t.is_active = true), 0) as balance
from public.customers c
left join public.invoices i on i.customer_id = c.id and i.is_active = true
where c.is_active = true
group by c.id, c.name, c.account_type, c.currency, c.opening_balance;

-- 12. INDEXES
create index if not exists idx_invoices_customer on public.invoices (customer_id);
create index if not exists idx_invoices_date on public.invoices (invoice_date);
create index if not exists idx_invoices_status on public.invoices (status);
create index if not exists idx_invoices_type on public.invoices (invoice_type);
create index if not exists idx_invoice_items_invoice on public.invoice_items (invoice_id);
create index if not exists idx_products_code on public.products (code);
create index if not exists idx_products_category on public.products (category);
create index if not exists idx_stock_movements_product on public.stock_movements (product_id);
create index if not exists idx_transactions_customer on public.transactions (customer_id);
create index if not exists idx_transactions_date on public.transactions (transaction_date);
create index if not exists idx_service_parts_service on public.service_parts (service_id);

-- 13. RLS POLİCİES
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.products enable row level security;
alter table public.stock_movements enable row level security;
alter table public.transactions enable row level security;
alter table public.service_parts enable row level security;
alter table public.invoice_settings enable row level security;

-- Invoices
drop policy if exists "invoices_select" on public.invoices;
create policy "invoices_select" on public.invoices for select to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "invoices_insert" on public.invoices;
create policy "invoices_insert" on public.invoices for insert to authenticated
with check (true);

drop policy if exists "invoices_update" on public.invoices;
create policy "invoices_update" on public.invoices for update to authenticated
using (public.is_admin() or is_active = true);

-- Invoice Items
drop policy if exists "invoice_items_select" on public.invoice_items;
create policy "invoice_items_select" on public.invoice_items for select to authenticated using (true);

drop policy if exists "invoice_items_insert" on public.invoice_items;
create policy "invoice_items_insert" on public.invoice_items for insert to authenticated with check (true);

drop policy if exists "invoice_items_update" on public.invoice_items;
create policy "invoice_items_update" on public.invoice_items for update to authenticated using (true);

drop policy if exists "invoice_items_delete" on public.invoice_items;
create policy "invoice_items_delete" on public.invoice_items for delete to authenticated using (true);

-- Products
drop policy if exists "products_select" on public.products;
create policy "products_select" on public.products for select to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "products_insert" on public.products;
create policy "products_insert" on public.products for insert to authenticated with check (true);

drop policy if exists "products_update" on public.products;
create policy "products_update" on public.products for update to authenticated using (true);

-- Stock Movements
drop policy if exists "stock_movements_select" on public.stock_movements;
create policy "stock_movements_select" on public.stock_movements for select to authenticated using (true);

drop policy if exists "stock_movements_insert" on public.stock_movements;
create policy "stock_movements_insert" on public.stock_movements for insert to authenticated with check (true);

-- Transactions
drop policy if exists "transactions_select" on public.transactions;
create policy "transactions_select" on public.transactions for select to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "transactions_insert" on public.transactions;
create policy "transactions_insert" on public.transactions for insert to authenticated with check (true);

drop policy if exists "transactions_update" on public.transactions;
create policy "transactions_update" on public.transactions for update to authenticated using (true);

-- Service Parts
drop policy if exists "service_parts_select" on public.service_parts;
create policy "service_parts_select" on public.service_parts for select to authenticated using (true);

drop policy if exists "service_parts_insert" on public.service_parts;
create policy "service_parts_insert" on public.service_parts for insert to authenticated with check (true);

drop policy if exists "service_parts_update" on public.service_parts;
create policy "service_parts_update" on public.service_parts for update to authenticated using (true);

drop policy if exists "service_parts_delete" on public.service_parts;
create policy "service_parts_delete" on public.service_parts for delete to authenticated using (true);

-- Invoice Settings
drop policy if exists "invoice_settings_select" on public.invoice_settings;
create policy "invoice_settings_select" on public.invoice_settings for select to authenticated using (true);

drop policy if exists "invoice_settings_update" on public.invoice_settings;
create policy "invoice_settings_update" on public.invoice_settings for update to authenticated using (public.is_admin());

-- 14. FATURA NUMARASI OLUŞTURMA FONKSİYONU
create or replace function public.generate_invoice_number(p_invoice_type text)
returns text
language plpgsql
security definer
as $$
declare
  v_prefix text;
  v_next_number integer;
  v_year integer;
  v_invoice_number text;
begin
  v_year := extract(year from current_date);
  
  -- Mevcut ayarları al ve kilitle
  select prefix, next_number into v_prefix, v_next_number
  from public.invoice_settings
  where invoice_type = p_invoice_type and year = v_year
  for update;
  
  -- Yoksa oluştur
  if not found then
    v_prefix := case when p_invoice_type = 'purchase' then 'ALŞ' else 'STŞ' end;
    v_next_number := 1;
    
    insert into public.invoice_settings (invoice_type, prefix, next_number, year)
    values (p_invoice_type, v_prefix, v_next_number + 1, v_year);
  else
    -- Numarayı artır
    update public.invoice_settings
    set next_number = next_number + 1
    where invoice_type = p_invoice_type and year = v_year;
  end if;
  
  -- Fatura numarası oluştur
  v_invoice_number := v_prefix || '-' || v_year || '-' || lpad(v_next_number::text, 6, '0');
  
  return v_invoice_number;
end;
$$;

-- 15. FATURA TOPLAM GÜNCELLEME TRİGGERİ
create or replace function public.update_invoice_totals()
returns trigger
language plpgsql
security definer
as $$
declare
  v_subtotal numeric(14,2);
  v_tax_total numeric(14,2);
  v_discount_total numeric(14,2);
  v_grand_total numeric(14,2);
begin
  -- Toplamları hesapla
  select 
    coalesce(sum(unit_price * quantity), 0),
    coalesce(sum(tax_amount), 0),
    coalesce(sum(discount_amount), 0),
    coalesce(sum(line_total), 0)
  into v_subtotal, v_tax_total, v_discount_total, v_grand_total
  from public.invoice_items
  where invoice_id = coalesce(new.invoice_id, old.invoice_id);
  
  -- Faturayı güncelle
  update public.invoices
  set 
    subtotal = v_subtotal,
    tax_total = v_tax_total,
    discount_total = v_discount_total,
    grand_total = v_grand_total,
    updated_at = now()
  where id = coalesce(new.invoice_id, old.invoice_id);
  
  return new;
end;
$$;

drop trigger if exists trigger_update_invoice_totals on public.invoice_items;
create trigger trigger_update_invoice_totals
after insert or update or delete on public.invoice_items
for each row execute procedure public.update_invoice_totals();

-- 16. FATURA DURUMU GÜNCELLEME
create or replace function public.update_invoice_status()
returns trigger
language plpgsql
security definer
as $$
declare
  v_paid numeric(14,2);
  v_total numeric(14,2);
  v_new_status text;
begin
  -- Toplam ödeme miktarını hesapla
  select coalesce(sum(amount), 0) into v_paid
  from public.transactions
  where invoice_id = coalesce(new.invoice_id, old.invoice_id) and is_active = true;
  
  -- Fatura toplamını al
  select grand_total into v_total
  from public.invoices
  where id = coalesce(new.invoice_id, old.invoice_id);
  
  -- Durumu belirle
  if v_paid >= v_total then
    v_new_status := 'paid';
  elsif v_paid > 0 then
    v_new_status := 'partial';
  else
    v_new_status := 'open';
  end if;
  
  -- Faturayı güncelle
  update public.invoices
  set 
    paid_amount = v_paid,
    status = v_new_status,
    updated_at = now()
  where id = coalesce(new.invoice_id, old.invoice_id)
    and status not in ('draft', 'cancelled');
  
  return new;
end;
$$;

drop trigger if exists trigger_update_invoice_status on public.transactions;
create trigger trigger_update_invoice_status
after insert or update or delete on public.transactions
for each row
execute procedure public.update_invoice_status();
