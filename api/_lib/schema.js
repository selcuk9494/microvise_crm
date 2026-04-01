const { query } = require('./db');

const ensured = {
  serial_tracking: false,
  work_order_close_notes: false,
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

module.exports = {
  ensureSerialTrackingTable,
  ensureWorkOrderCloseNotesTable,
};
