const { query } = require('./db');

const ensured = {
  serial_tracking: false,
  work_order_close_notes: false,
  invoice_items: false,
  fault_forms: false,
  device_registries: false,
  business_activity_types: false,
  work_order_signatures: false,
  work_orders_payment_required: false,
  work_orders_status_check: false,
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

async function ensureFaultFormsTable() {
  if (ensured.fault_forms) return true;

  const exists = await tableExists('fault_forms');
  if (!exists) {
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.fault_forms (
          id uuid primary key default gen_random_uuid(),
          form_date timestamptz not null default now(),
          customer_id uuid,
          customer_name text not null,
          customer_address text,
          customer_tax_office text,
          customer_vkn text,
          device_brand_model text,
          company_code_and_registry text,
          okc_approval_date_and_number text,
          fault_date_time_text text,
          fault_description text,
          last_z_report_date_and_number text,
          last_z_report_date timestamptz,
          last_z_report_no text,
          total_revenue text,
          total_vat text,
          is_active boolean not null default true,
          created_by uuid,
          created_at timestamptz not null default now()
        )
      `,
    );
  } else {
    await query(
      `
        alter table public.fault_forms
          add column if not exists form_date timestamptz,
          add column if not exists customer_id uuid,
          add column if not exists customer_name text,
          add column if not exists customer_address text,
          add column if not exists customer_tax_office text,
          add column if not exists customer_vkn text,
          add column if not exists device_brand_model text,
          add column if not exists company_code_and_registry text,
          add column if not exists okc_approval_date_and_number text,
          add column if not exists fault_date_time_text text,
          add column if not exists fault_description text,
          add column if not exists last_z_report_date_and_number text,
          add column if not exists last_z_report_date timestamptz,
          add column if not exists last_z_report_no text,
          add column if not exists total_revenue text,
          add column if not exists total_vat text,
          add column if not exists is_active boolean,
          add column if not exists created_by uuid,
          add column if not exists created_at timestamptz
      `,
    );
  }

  ensured.fault_forms = true;
  return true;
}

async function ensureDeviceRegistriesTable() {
  if (ensured.device_registries) return true;

  const exists = await tableExists('device_registries');
  if (!exists) {
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.device_registries (
          id uuid primary key default gen_random_uuid(),
          registry_number text not null,
          registry_number_norm text not null,
          model text,
          customer_id uuid,
          application_form_id uuid,
          is_active boolean not null default true,
          assigned_at timestamptz,
          released_at timestamptz,
          created_by uuid,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create unique index if not exists idx_device_registries_unique_registry_norm
        on public.device_registries (registry_number_norm)
      `,
    );
    await query(
      `
        create index if not exists idx_device_registries_customer_id
        on public.device_registries (customer_id)
      `,
    );
    await query(
      `
        create index if not exists idx_device_registries_created_at
        on public.device_registries (created_at desc)
      `,
    );
    await query(
      `
        create or replace function public.device_registries_set_updated_at()
        returns trigger
        language plpgsql
        as $$
        begin
          new.registry_number_norm = upper(btrim(new.registry_number));
          new.updated_at = now();
          return new;
        end;
        $$;
      `,
    );
    await query(
      `
        drop trigger if exists set_device_registries_updated_at on public.device_registries;
        create trigger set_device_registries_updated_at
        before insert or update on public.device_registries
        for each row
        execute function public.device_registries_set_updated_at();
      `,
    );
  } else {
    await query(
      `
        alter table public.device_registries
          add column if not exists registry_number text,
          add column if not exists registry_number_norm text,
          add column if not exists model text,
          add column if not exists customer_id uuid,
          add column if not exists application_form_id uuid,
          add column if not exists is_active boolean,
          add column if not exists assigned_at timestamptz,
          add column if not exists released_at timestamptz,
          add column if not exists created_by uuid,
          add column if not exists created_at timestamptz,
          add column if not exists updated_at timestamptz
      `,
    );
    await query(
      `
        update public.device_registries
        set registry_number_norm = upper(btrim(registry_number))
        where coalesce(registry_number_norm, '') = ''
      `,
    );
    await query(
      `
        create unique index if not exists idx_device_registries_unique_registry_norm
        on public.device_registries (registry_number_norm)
      `,
    );
    await query(
      `
        create index if not exists idx_device_registries_customer_id
        on public.device_registries (customer_id)
      `,
    );
    await query(
      `
        create index if not exists idx_device_registries_created_at
        on public.device_registries (created_at desc)
      `,
    );
    await query(
      `
        create or replace function public.device_registries_set_updated_at()
        returns trigger
        language plpgsql
        as $$
        begin
          new.registry_number_norm = upper(btrim(new.registry_number));
          new.updated_at = now();
          return new;
        end;
        $$;
      `,
    );
    await query(
      `
        drop trigger if exists set_device_registries_updated_at on public.device_registries;
        create trigger set_device_registries_updated_at
        before insert or update on public.device_registries
        for each row
        execute function public.device_registries_set_updated_at();
      `,
    );
  }

  ensured.device_registries = true;
  return true;
}

async function ensureBusinessActivityTypesTable() {
  if (ensured.business_activity_types) return true;

  const exists = await tableExists('business_activity_types');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'business_activity_types table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.business_activity_types (
          id uuid primary key default gen_random_uuid(),
          name text not null,
          is_active boolean not null default true,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create unique index if not exists idx_business_activity_types_unique_name
        on public.business_activity_types (upper(btrim(name)))
      `,
    );
    await query(
      `
        create or replace function public.business_activity_types_set_updated_at()
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
        drop trigger if exists set_business_activity_types_updated_at on public.business_activity_types;
        create trigger set_business_activity_types_updated_at
        before update on public.business_activity_types
        for each row
        execute function public.business_activity_types_set_updated_at();
      `,
    );
  }

  ensured.business_activity_types = true;
  return true;
}

async function ensureWorkOrderSignaturesTable() {
  if (ensured.work_order_signatures) return true;

  const exists = await tableExists('work_order_signatures');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'work_order_signatures table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.work_order_signatures (
          id uuid primary key default gen_random_uuid(),
          work_order_id uuid not null unique,
          customer_signature_data_url text,
          personnel_signature_data_url text,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create index if not exists idx_work_order_signatures_work_order_id
        on public.work_order_signatures (work_order_id)
      `,
    );
    await query(
      `
        create or replace function public.work_order_signatures_set_updated_at()
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
        drop trigger if exists set_work_order_signatures_updated_at on public.work_order_signatures;
        create trigger set_work_order_signatures_updated_at
        before update on public.work_order_signatures
        for each row
        execute function public.work_order_signatures_set_updated_at();
      `,
    );
  } else {
    await query(
      `
        alter table public.work_order_signatures
          add column if not exists id uuid,
          add column if not exists work_order_id uuid,
          add column if not exists customer_signature_data_url text,
          add column if not exists personnel_signature_data_url text,
          add column if not exists created_at timestamptz,
          add column if not exists updated_at timestamptz
      `,
    );
    await query(
      `
        create index if not exists idx_work_order_signatures_work_order_id
        on public.work_order_signatures (work_order_id)
      `,
    );
    await query(
      `
        create or replace function public.work_order_signatures_set_updated_at()
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
        drop trigger if exists set_work_order_signatures_updated_at on public.work_order_signatures;
        create trigger set_work_order_signatures_updated_at
        before update on public.work_order_signatures
        for each row
        execute function public.work_order_signatures_set_updated_at();
      `,
    );
  }

  ensured.work_order_signatures = true;
  return true;
}

async function ensureWorkOrdersPaymentRequiredColumn() {
  if (ensured.work_orders_payment_required) return true;

  const exists = await tableExists('work_orders');
  if (exists) {
    await query(
      `
        alter table public.work_orders
          add column if not exists payment_required boolean not null default true
      `,
    );
  }

  ensured.work_orders_payment_required = true;
  return true;
}

async function ensureWorkOrdersStatusCheckConstraint() {
  if (ensured.work_orders_status_check) return true;

  const exists = await tableExists('work_orders');
  if (exists) {
    await query(
      `
        alter table public.work_orders
          drop constraint if exists work_orders_status_check
      `,
    );
    await query(
      `
        alter table public.work_orders
          add constraint work_orders_status_check
          check (status in ('open','in_progress','approval_pending','done','cancelled'))
      `,
    );
  }

  ensured.work_orders_status_check = true;
  return true;
}

module.exports = {
  ensureSerialTrackingTable,
  ensureWorkOrderCloseNotesTable,
  ensureInvoiceItemsTable,
  ensureFaultFormsTable,
  ensureDeviceRegistriesTable,
  ensureBusinessActivityTypesTable,
  ensureWorkOrderSignaturesTable,
  ensureWorkOrdersPaymentRequiredColumn,
  ensureWorkOrdersStatusCheckConstraint,
};
