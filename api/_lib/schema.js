const { query } = require('./db');

const ensured = {
  serial_tracking: false,
  work_order_close_notes: false,
  invoice_items: false,
  fault_forms: false,
  device_registries: false,
  business_activity_types: false,
  software_companies: false,
  licenses_software_company: false,
  licenses_registry_number: false,
  lines_operator: false,
  line_stock: false,
  users_auth: false,
  region_colors: false,
  service_fault_types: false,
  service_accessory_types: false,
  service_records_columns: false,
  service_records_status_check: false,
  service_records_extended: false,
  service_activity_logs: false,
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

async function ensureUsersAuthColumns() {
  if (ensured.users_auth) return true;

  const exists = await tableExists('users');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'users table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.users (
          id uuid primary key default gen_random_uuid(),
          email text not null,
          full_name text,
          role text not null default 'personel',
          page_permissions text[] not null default '{}'::text[],
          action_permissions text[] not null default '{}'::text[],
          password_hash text,
          is_active boolean not null default true,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create unique index if not exists idx_users_unique_email
        on public.users (lower(email))
      `,
    );
  } else {
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        alter table public.users
          add column if not exists password_hash text,
          add column if not exists is_active boolean,
          add column if not exists created_at timestamptz,
          add column if not exists updated_at timestamptz
      `,
    );
    await query(
      `
        update public.users
        set
          is_active = coalesce(is_active, true),
          created_at = coalesce(created_at, now()),
          updated_at = coalesce(updated_at, now())
        where is_active is null or created_at is null or updated_at is null
      `,
    );
    await query(
      `
        alter table public.users
          alter column is_active set default true
      `,
    );
  }

  await query(
    `
      create or replace function public.users_set_updated_at()
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
      drop trigger if exists set_users_updated_at on public.users;
      create trigger set_users_updated_at
      before update on public.users
      for each row
      execute function public.users_set_updated_at();
    `,
  );

  ensured.users_auth = true;
  return true;
}

async function ensureRegionColorsTable() {
  if (ensured.region_colors) return true;

  await query(
    `
      create table if not exists public.region_colors (
        region_key text primary key,
        label text not null,
        bg_color text not null,
        border_color text not null,
        sort_order int not null default 0,
        is_active boolean not null default true,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )
    `,
  );

  await query(
    `
      create or replace function public.region_colors_set_updated_at()
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
      drop trigger if exists set_region_colors_updated_at on public.region_colors;
      create trigger set_region_colors_updated_at
      before update on public.region_colors
      for each row
      execute function public.region_colors_set_updated_at();
    `,
  );

  await query(
    `
      insert into public.region_colors (region_key, label, bg_color, border_color, sort_order, is_active)
      values
        ('girne', 'Girne', '#EEF2FF', '#364FC7', 10, true),
        ('guzelyurt', 'Güzelyurt', '#EBFBEE', '#2B8A3E', 20, true),
        ('iskele', 'İskele', '#FFF9DB', '#F59F00', 30, true),
        ('magusa', 'Gazimağusa', '#FFF4E6', '#F76707', 40, true),
        ('lefke', 'Lefke', '#F1F3F5', '#495057', 50, true),
        ('lefkosa', 'Lefkoşa', '#FFF8F0', '#7C4A2D', 60, true)
      on conflict (region_key) do nothing
    `,
  );

  ensured.region_colors = true;
  return true;
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

async function ensureSoftwareCompaniesTable() {
  if (ensured.software_companies) return true;

  const exists = await tableExists('software_companies');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'software_companies table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.software_companies (
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
        create unique index if not exists idx_software_companies_unique_name
        on public.software_companies (upper(btrim(name)))
      `,
    );
    await query(
      `
        create or replace function public.software_companies_set_updated_at()
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
        drop trigger if exists set_software_companies_updated_at on public.software_companies;
        create trigger set_software_companies_updated_at
        before update on public.software_companies
        for each row
        execute function public.software_companies_set_updated_at();
      `,
    );
  }

  ensured.software_companies = true;
  return true;
}

async function ensureLicensesSoftwareCompanyColumn() {
  if (ensured.licenses_software_company) return true;
  const exists = await tableExists('licenses');
  if (exists) {
    await query(
      `
        alter table public.licenses
          add column if not exists software_company_id uuid
      `,
    );
    await query(
      `
        create index if not exists idx_licenses_software_company_id
        on public.licenses (software_company_id)
      `,
    );
  }
  ensured.licenses_software_company = true;
  return true;
}

async function ensureLicensesRegistryNumberColumn() {
  if (ensured.licenses_registry_number) return true;
  const exists = await tableExists('licenses');
  if (exists) {
    await query(
      `
        alter table public.licenses
          add column if not exists registry_number text
      `,
    );
    await query(
      `
        create index if not exists idx_licenses_registry_number
        on public.licenses (registry_number)
      `,
    );
  }
  ensured.licenses_registry_number = true;
  return true;
}

async function ensureLinesOperatorColumn() {
  if (ensured.lines_operator) return true;
  const exists = await tableExists('lines');
  if (exists) {
    await query(
      `
        alter table public.lines
          add column if not exists operator text
      `,
    );
    await query(
      `
        create index if not exists idx_lines_operator
        on public.lines (operator)
      `,
    );
  }
  ensured.lines_operator = true;
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

async function ensureLineStockTable() {
  if (ensured.line_stock) return true;

  const exists = await tableExists('line_stock');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'line_stock table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.line_stock (
          id uuid primary key default gen_random_uuid(),
          operator text not null default 'turkcell',
          line_number text not null,
          line_number_norm text not null,
          sim_number text,
          sim_number_norm text,
          is_active boolean not null default true,
          consumed_at timestamptz,
          consumed_by uuid,
          consumed_customer_id uuid,
          consumed_work_order_id uuid,
          consumed_line_id uuid,
          created_by uuid,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create unique index if not exists idx_line_stock_unique_line_number
        on public.line_stock (line_number_norm)
      `,
    );
    await query(
      `
        create unique index if not exists idx_line_stock_unique_sim_number
        on public.line_stock (sim_number_norm)
        where sim_number_norm is not null and sim_number_norm <> ''
      `,
    );
    await query(
      `
        create index if not exists idx_line_stock_available
        on public.line_stock (is_active, consumed_at)
      `,
    );
    await query(
      `
        create or replace function public.line_stock_set_updated_at()
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
        drop trigger if exists set_line_stock_updated_at on public.line_stock;
        create trigger set_line_stock_updated_at
        before update on public.line_stock
        for each row
        execute function public.line_stock_set_updated_at();
      `,
    );
  }

  ensured.line_stock = true;
  return true;
}

async function ensureServiceFaultTypesTable() {
  if (ensured.service_fault_types) return true;

  const exists = await tableExists('service_fault_types');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'service_fault_types table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.service_fault_types (
          id uuid primary key default gen_random_uuid(),
          name text not null,
          sort_order int not null default 0,
          is_active boolean not null default true,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create unique index if not exists idx_service_fault_types_unique_name
        on public.service_fault_types (upper(btrim(name)))
      `,
    );
    await query(
      `
        create or replace function public.service_fault_types_set_updated_at()
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
        drop trigger if exists set_service_fault_types_updated_at on public.service_fault_types;
        create trigger set_service_fault_types_updated_at
        before update on public.service_fault_types
        for each row
        execute function public.service_fault_types_set_updated_at();
      `,
    );
  }

  ensured.service_fault_types = true;
  return true;
}

async function ensureServiceAccessoryTypesTable() {
  if (ensured.service_accessory_types) return true;

  const exists = await tableExists('service_accessory_types');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'service_accessory_types table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.service_accessory_types (
          id uuid primary key default gen_random_uuid(),
          name text not null,
          sort_order int not null default 0,
          is_active boolean not null default true,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create unique index if not exists idx_service_accessory_types_unique_name
        on public.service_accessory_types (upper(btrim(name)))
      `,
    );
    await query(
      `
        create or replace function public.service_accessory_types_set_updated_at()
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
        drop trigger if exists set_service_accessory_types_updated_at on public.service_accessory_types;
        create trigger set_service_accessory_types_updated_at
        before update on public.service_accessory_types
        for each row
        execute function public.service_accessory_types_set_updated_at();
      `,
    );
  }

  ensured.service_accessory_types = true;
  return true;
}

async function ensureServiceRecordsColumns() {
  if (ensured.service_records_columns) return true;

  const exists = await tableExists('service_records');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'service_records table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.service_records (
          id uuid primary key default gen_random_uuid(),
          customer_id uuid,
          device_id uuid,
          title text,
          status text not null default 'waiting',
          notes text,
          registry_number text,
          fault_type_id uuid,
          accessories_received boolean not null default false,
          accessory_type_ids jsonb,
          device_images jsonb,
          intake_customer_signature_data_url text,
          intake_personnel_signature_data_url text,
          delivery_customer_signature_data_url text,
          delivery_personnel_signature_data_url text,
          steps jsonb,
          parts jsonb,
          labor jsonb,
          total_amount numeric,
          currency text,
          is_active boolean not null default true,
          created_at timestamptz not null default now()
        )
      `,
    );
  } else {
    await query(
      `
        alter table public.service_records
          add column if not exists notes text,
          add column if not exists registry_number text,
          add column if not exists fault_type_id uuid,
          add column if not exists accessories_received boolean,
          add column if not exists accessory_type_ids jsonb,
          add column if not exists device_images jsonb,
          add column if not exists intake_customer_signature_data_url text,
          add column if not exists intake_personnel_signature_data_url text,
          add column if not exists delivery_customer_signature_data_url text,
          add column if not exists delivery_personnel_signature_data_url text
      `,
    );
  }

  ensured.service_records_columns = true;
  return true;
}

async function ensureServiceRecordsExtendedColumns() {
  if (ensured.service_records_extended) return true;

  const exists = await tableExists('service_records');
  if (exists) {
    await query(`create extension if not exists pgcrypto`);
    await query(`create sequence if not exists public.service_no_seq`);
    await query(
      `
        alter table public.service_records
          add column if not exists service_no bigint,
          add column if not exists priority text,
          add column if not exists technician_id uuid,
          add column if not exists appointment_at timestamptz,
          add column if not exists fault_description text,
          add column if not exists device_brand text,
          add column if not exists device_model text,
          add column if not exists device_serial text,
          add column if not exists cancelled_reason text,
          add column if not exists cancelled_at timestamptz,
          add column if not exists updated_at timestamptz not null default now()
      `,
    );
    await query(
      `
        alter table public.service_records
          alter column service_no set default nextval('public.service_no_seq')
      `,
    );
    await query(
      `
        update public.service_records
        set service_no = nextval('public.service_no_seq')
        where service_no is null
      `,
    );
    await query(
      `
        create unique index if not exists idx_service_records_service_no
        on public.service_records (service_no)
      `,
    );
    await query(
      `
        create index if not exists idx_service_records_status_created_at
        on public.service_records (status, created_at desc)
      `,
    );
    await query(
      `
        create index if not exists idx_service_records_technician_created_at
        on public.service_records (technician_id, created_at desc)
      `,
    );
    await query(
      `
        create or replace function public.service_records_set_updated_at()
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
        drop trigger if exists set_service_records_updated_at on public.service_records;
        create trigger set_service_records_updated_at
        before update on public.service_records
        for each row
        execute function public.service_records_set_updated_at();
      `,
    );
  }

  ensured.service_records_extended = true;
  return true;
}

async function ensureServiceRecordsStatusCheckConstraint() {
  if (ensured.service_records_status_check) return true;

  const exists = await tableExists('service_records');
  if (exists) {
    await query(
      `
        alter table public.service_records
          drop constraint if exists service_records_status_check
      `,
    );
    await query(
      `
        alter table public.service_records
          add constraint service_records_status_check
          check (status in ('open','in_progress','waiting','approval','ready','done','cancelled'))
      `,
    );
  }

  ensured.service_records_status_check = true;
  return true;
}

async function ensureServiceActivityLogsTable() {
  if (ensured.service_activity_logs) return true;

  const exists = await tableExists('service_activity_logs');
  if (!exists) {
    const isProd = process.env.NODE_ENV === 'production';
    const allow = String(process.env.ALLOW_SCHEMA_AUTO_CREATE || '').trim();
    if (isProd && allow !== 'true') {
      throw new Error(
        'service_activity_logs table is missing. Set ALLOW_SCHEMA_AUTO_CREATE=true to auto-create (non-production recommended).',
      );
    }
    await query(`create extension if not exists pgcrypto`);
    await query(
      `
        create table if not exists public.service_activity_logs (
          id uuid primary key default gen_random_uuid(),
          service_id uuid not null,
          type text not null default 'note',
          message text,
          meta jsonb,
          created_by uuid,
          created_at timestamptz not null default now()
        )
      `,
    );
    await query(
      `
        create index if not exists idx_service_activity_logs_service_created_at
        on public.service_activity_logs (service_id, created_at desc)
      `,
    );
  }

  ensured.service_activity_logs = true;
  return true;
}

module.exports = {
  ensureSerialTrackingTable,
  ensureUsersAuthColumns,
  ensureRegionColorsTable,
  ensureWorkOrderCloseNotesTable,
  ensureInvoiceItemsTable,
  ensureFaultFormsTable,
  ensureDeviceRegistriesTable,
  ensureBusinessActivityTypesTable,
  ensureSoftwareCompaniesTable,
  ensureLicensesSoftwareCompanyColumn,
  ensureLicensesRegistryNumberColumn,
  ensureLinesOperatorColumn,
  ensureLineStockTable,
  ensureServiceFaultTypesTable,
  ensureServiceAccessoryTypesTable,
  ensureServiceRecordsColumns,
  ensureServiceRecordsExtendedColumns,
  ensureServiceRecordsStatusCheckConstraint,
  ensureServiceActivityLogsTable,
  ensureWorkOrderSignaturesTable,
  ensureWorkOrdersPaymentRequiredColumn,
  ensureWorkOrdersStatusCheckConstraint,
};
