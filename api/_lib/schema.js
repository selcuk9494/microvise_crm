const { query } = require('./db');

const ensured = {
  serial_tracking: false,
  work_order_close_notes: false,
  invoice_items: false,
};

async function tableExists(tableName) {
  const result = await query(
    `
      select 1 as ok
      from information_schema.tables
      where table_schema = 'public'
        and table_name = $1
      limit 1
    `,
    [tableName],
  );
  return (result.rows[0]?.ok ?? null) === 1;
}

async function ensureSerialTrackingTable() {
  if (ensured.serial_tracking) return;

  const exists = await tableExists('serial_tracking');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'serial_tracking table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.serial_tracking (
          id uuid primary key default gen_random_uuid(),
          product_name text not null,
          serial_number text not null,
          is_active boolean not null default true,
          created_by uuid,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create unique index if not exists idx_serial_tracking_unique_serial
        on public.serial_tracking (upper(btrim(serial_number)))
      `,
    );
    await query(
      `
        create index if not exists idx_serial_tracking_created_at
        on public.serial_tracking (created_at desc)
      `,
    );
    await query(
      `
        create or replace function public.serial_tracking_set_updated_at()
        returns trigger
        language plpgsql
        as $$
        begin
          new.updated_at = now();
          return new;
        end;
        $$;
      `,
    );
    await query(
      `
        drop trigger if exists set_serial_tracking_updated_at on public.serial_tracking;
        create trigger set_serial_tracking_updated_at
        before update on public.serial_tracking
        for each row
        execute function public.serial_tracking_set_updated_at();
      `,
    );
  }

  ensured.serial_tracking = true;
}

async function ensureWorkOrderCloseNotesTable() {
  if (ensured.work_order_close_notes) return;

  const exists = await tableExists('work_order_close_notes');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'work_order_close_notes table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.work_order_close_notes (
          id uuid primary key default gen_random_uuid(),
          name text not null unique,
          is_active boolean not null default true,
          sort_order integer default 0,
          created_at timestamptz not null default now()
        )
      `,
    );
  }

  await query(
    `
      insert into public.work_order_close_notes (name, sort_order)
      values
        ('Kurulum tamamlandı', 1),
        ('Arıza giderildi', 2),
        ('Bakım yapıldı', 3),
        ('Müşteri yerinde yok', 4),
        ('Erişim sağlanamadı', 5)
      on conflict (name) do nothing
    `,
  );

  ensured.work_order_close_notes = true;
}

async function ensureInvoiceItemsTable() {
  if (ensured.invoice_items) return true;

  const exists = await tableExists('invoice_items');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      ensured.invoice_items = true;
      return false;
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.invoice_items (
          id uuid primary key default gen_random_uuid(),
          customer_id uuid,
          item_type text not null default 'work_order_payment',
          source_table text not null default 'work_orders',
          source_id uuid not null,
          source_event text,
          source_label text,
          description text,
          amount numeric,
          currency text not null default 'TRY',
          status text not null default 'pending',
          is_active boolean not null default true,
          invoiced_at timestamptz,
          approved_by uuid,
          approved_at timestamptz,
          updated_by uuid,
          updated_at timestamptz,
          deactivated_by uuid,
          deactivated_at timestamptz,
          created_by uuid,
          created_at timestamptz not null default now()
        )
      `,
    );
  }

  await query(
    `
      alter table public.invoice_items
        add column if not exists customer_id uuid,
        add column if not exists item_type text,
        add column if not exists source_table text,
        add column if not exists source_id uuid,
        add column if not exists source_event text,
        add column if not exists source_label text,
        add column if not exists description text,
        add column if not exists amount numeric,
        add column if not exists currency text,
        add column if not exists status text,
        add column if not exists is_active boolean,
        add column if not exists invoiced_at timestamptz,
        add column if not exists approved_by uuid,
        add column if not exists approved_at timestamptz,
        add column if not exists updated_by uuid,
        add column if not exists updated_at timestamptz,
        add column if not exists deactivated_by uuid,
        add column if not exists deactivated_at timestamptz,
        add column if not exists created_by uuid,
        add column if not exists created_at timestamptz
    `,
  );

  const colsResult = await query(
    `
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'invoice_items'
    `,
  );
  const cols = colsResult.rows.map((r) => r.column_name);
  if (cols.includes('item_type')) {
    await query(
      `alter table public.invoice_items drop constraint if exists invoice_items_item_type_check`,
    );
  }
  if (cols.includes('source_table')) {
    await query(
      `alter table public.invoice_items drop constraint if exists invoice_items_source_table_check`,
    );
  }

  ensured.invoice_items = true;
  return true;
}

module.exports = {
  ensureSerialTrackingTable,
  ensureWorkOrderCloseNotesTable,
  ensureInvoiceItemsTable,
};
