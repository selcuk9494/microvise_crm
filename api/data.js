const {
  getAuthenticatedUser,
  hasPageAccess,
  isBankAdminLikeUser,
  isBankLikeUser,
} = require('./_lib/auth');
const { query } = require('./_lib/db');
const https = require('https');
const {
  ensureSerialTrackingTable,
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
  ensureFinanceTables,
  ensureApplicationFormsApprovalColumns,
  ensureApplicationFormActivityLogsTable,
} = require('./_lib/schema');
const {
  handleCors,
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
  parseBoolean,
  parseInteger,
} = require('./_lib/http');

let halkbankRatesCache = { fetchedAtMs: 0, payload: null };

function fetchText(url, { timeoutMs = 9000 } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.get(
      url,
      {
        headers: {
          'user-agent': 'microvise-crm/1.0',
          accept: 'text/html,*/*',
          'accept-encoding': 'identity',
        },
      },
      (res) => {
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => resolve(data));
      },
    );
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error('timeout'));
    });
  });
}

function parseTrNumber(input) {
  const v = String(input || '').trim();
  if (!v) return null;
  const normalized = v.replace(/\./g, '').replace(',', '.');
  const n = Number.parseFloat(normalized);
  return Number.isFinite(n) ? n : null;
}

function parseHalkbankRow(html, slug, code) {
  const idx = html.indexOf(`/halkbank/${slug}`);
  if (idx < 0) return null;
  const slice = html.substring(idx, Math.min(html.length, idx + 1000));
  const bold = [...slice.matchAll(/<td class="text-bold"[^>]*>([^<]+)<\/td>/g)].map((m) =>
    String(m[1] || '').trim(),
  );
  const timeMatch = slice.match(/<td class="time">([^<]+)<\/td>/);
  const buying = parseTrNumber(bold[0]);
  const selling = parseTrNumber(bold[1]);
  const time = timeMatch ? String(timeMatch[1] || '').trim() : null;
  if (buying == null || selling == null) return null;
  return { code, buying, selling, time };
}

function requirePage(req, user, pageKey, res) {
  if (!hasPageAccess(user, pageKey)) {
    forbidden(req, res, 'Erişim yetkiniz yok.');
    return false;
  }
  return true;
}

function requireAnyPage(req, user, pageKeys, res) {
  const keys = Array.isArray(pageKeys)
    ? pageKeys
    : [String(pageKeys || '').trim()].filter((k) => k.length > 0);
  if (!keys.length) return true;
  for (const key of keys) {
    if (hasPageAccess(user, key)) return true;
  }
  forbidden(req, res, 'Erişim yetkiniz yok.');
  return false;
}

const columnsCache = new Map();

async function getTableColumns(tableName) {
  if (columnsCache.has(tableName)) return columnsCache.get(tableName);
  const result = await query(
    `
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = $1
      order by ordinal_position asc
    `,
    [tableName],
  );
  const columns = result.rows
    .map((r) => r.column_name)
    .filter((c) => typeof c === 'string' && c.length > 0);
  columnsCache.set(tableName, columns);
  return columns;
}

module.exports = async (req, res) => {
  if (handleCors(req, res)) return;
  if (req.method !== 'GET') {
    return methodNotAllowed(req, res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);

    const resource = String(req.query.resource || '').trim();
    if (!resource) return badRequest(req, res, 'resource zorunludur.');

    if (
      resource.startsWith('customer') ||
      resource === 'customers_for_transfer' ||
      resource === 'customer_branches' ||
      resource === 'customer_lines' ||
      resource === 'customer_licenses' ||
      resource === 'customer_work_orders'
    ) {
      if (!requirePage(req, user, 'musteriler', res)) return;
    }
    if (resource.startsWith('service')) {
      if (!requirePage(req, user, 'servis', res)) return;
    }
    if (resource.startsWith('definition_')) {
      if (resource === 'definition_work_order_types') {
        if (!requireAnyPage(req, user, ['tanimlamalar', 'is_emirleri', 'formlar'], res))
          return;
      } else if (resource === 'definition_work_order_close_notes') {
        if (!requireAnyPage(req, user, ['tanimlamalar', 'is_emirleri'], res)) return;
      } else if (
        resource === 'definition_service_fault_types' ||
        resource === 'definition_service_accessory_types'
      ) {
        if (!requireAnyPage(req, user, ['tanimlamalar', 'servis'], res)) return;
      } else if (resource === 'definition_cities') {
        if (!requireAnyPage(req, user, ['tanimlamalar', 'musteriler', 'is_emirleri', 'formlar'], res))
          return;
      } else if (
        resource === 'definition_device_brands' ||
        resource === 'definition_device_models' ||
        resource === 'definition_fiscal_symbols' ||
        resource === 'definition_business_activity_types'
      ) {
        if (!requireAnyPage(req, user, ['tanimlamalar', 'formlar'], res)) return;
      } else if (resource === 'definition_tax_rates') {
        if (!requireAnyPage(req, user, ['tanimlamalar', 'e_fatura', 'faturalama'], res)) return;
      } else {
        if (!requirePage(req, user, 'tanimlamalar', res)) return;
      }
    }
    if (resource.startsWith('personnel_')) {
      if (!requirePage(req, user, 'personel', res)) return;
    }
    if (resource === 'personnel_users') {
      if (!requireAnyPage(req, user, ['personel', 'is_emirleri', 'formlar'], res)) return;
    }
    if (resource.startsWith('products_') || resource === 'customers_lookup') {
      if (!requirePage(req, user, 'urunler', res)) return;
    }
    if (
      resource === 'application_form_print_settings' ||
      resource === 'scrap_form_print_settings' ||
      resource === 'transfer_form_print_settings'
    ) {
      if (!requirePage(req, user, 'formlar', res)) return;
    }
    if (resource === 'serial_tracking') {
      if (!requirePage(req, user, 'formlar', res)) return;
    }
    if (resource === 'serial_tracking_lookup') {
      if (!requirePage(req, user, 'formlar', res)) return;
    }
    if (resource === 'work_order_payments') {
      if (!requirePage(req, user, 'is_emirleri', res)) return;
    }
    if (resource.startsWith('finance_')) {
      if (!requirePage(req, user, 'finans', res)) return;
    }
    if (resource === 'halkbank_exchange_rates') {
      if (!requirePage(req, user, 'panel', res)) return;
    }
    if (resource === 'definition_region_colors') {
      if (!requirePage(req, user, 'tanimlamalar', res)) return;
    }
    if (resource.startsWith('form_')) {
      if (!requirePage(req, user, 'formlar', res)) return;
      if (
        isBankLikeUser(user) &&
        ![
          'form_customer_by_vkn',
          'form_customers_bulk',
          'form_application_list',
          'form_stock_products',
        ].includes(resource)
      ) {
        return forbidden(req, res, 'Banka kullanıcısı yalnızca başvuru formu verilerine erişebilir.');
      }
    }

    switch (resource) {
      case 'customers_basic': {
        const result = await query(
          `
            select id,name,city,address,is_active
            from public.customers
            where is_active = true
            order by name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customers_lookup_vkn': {
        if (!requirePage(req, user, 'musteriler', res)) return;
        const result = await query(
          `
            select id,name,vkn,is_active
            from public.customers
            order by name asc
            limit 5000
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_detail': {
        const id = String(req.query.customerId || '').trim();
        if (!id) return badRequest(req, res, 'customerId zorunludur.');
        const result = await query(
          `
            select
              id,
              name,
              city,
              address,
              director_name,
              email,
              vkn,
              tckn_ms,
              notes,
              phone_1,
              phone_1_title,
              phone_2,
              phone_2_title,
              phone_3,
              phone_3_title,
              is_active,
              created_at
            from public.customers
            where id = $1
            limit 1
          `,
          [id],
        );
        return ok(req, res, result.rows[0] || null);
      }

      case 'customer_lines': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(req, res, 'customerId zorunludur.');
        const showPassive = parseBoolean(req.query.showPassive, true);
        const values = [customerId];
        let activeSql = '';
        if (!showPassive) {
          values.push(true);
          activeSql = `and is_active = $${values.length}`;
        }
        await ensureLinesOperatorColumn();
        const result = await query(
          `
            select id,label,number,sim_number,operator,starts_at,ends_at,expires_at,is_active,created_at
            from public.lines
            where customer_id = $1
              ${activeSql}
            order by created_at desc
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_lines_numbers_bulk': {
        const idsRaw = String(req.query.ids || '').trim();
        if (!idsRaw) return ok(req, res, { items: [] });
        const ids = idsRaw
          .split(',')
          .map((id) => id.trim())
          .filter((id) => id.length > 0)
          .slice(0, 500);
        if (!ids.length) return ok(req, res, { items: [] });

        await ensureLinesOperatorColumn();
        const result = await query(
          `
            select distinct on (customer_id, number)
              id,
              customer_id,
              number,
              sim_number,
              operator,
              created_at
            from public.lines
            where is_active = true
              and customer_id::text = any($1::text[])
              and coalesce(number::text, '') <> ''
            order by customer_id, number, created_at desc
          `,
          [ids],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_locations': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(req, res, 'customerId zorunludur.');
        const result = await query(
          `
            select
              id,
              customer_id,
              title,
              description,
              address,
              location_link,
              location_lat,
              location_lng,
              is_active,
              created_at
            from public.customer_locations
            where customer_id = $1 and is_active = true
            order by created_at desc
          `,
          [customerId],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_licenses': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(req, res, 'customerId zorunludur.');
        const showPassive = parseBoolean(req.query.showPassive, true);
        const values = [customerId];
        let activeSql = '';
        if (!showPassive) {
          values.push(true);
          activeSql = `and is_active = $${values.length}`;
        }
        await ensureLicensesSoftwareCompanyColumn();
        await ensureLicensesRegistryNumberColumn();
        const result = await query(
          `
            select
              lic.id,
              lic.name,
              lic.license_type,
              lic.software_company_id,
              sc.name as software_company_name,
              lic.registry_number,
              lic.starts_at,
              lic.ends_at,
              lic.expires_at,
              lic.is_active,
              lic.created_at
            from public.licenses lic
            left join public.software_companies sc on sc.id = lic.software_company_id
            where lic.customer_id = $1
              ${activeSql.replaceAll('is_active', 'lic.is_active')}
            order by lic.created_at desc
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_device_registries': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(req, res, 'customerId zorunludur.');
        await ensureDeviceRegistriesTable();
        const showPassive = parseBoolean(req.query.showPassive, true);
        const values = [customerId];
        let activeSql = '';
        if (!showPassive) {
          values.push(true);
          activeSql = `and is_active = $${values.length}`;
        }
        const result = await query(
          `
            select
              id,
              registry_number,
              model,
              customer_id,
              application_form_id,
              is_active,
              assigned_at,
              released_at,
              created_at
            from public.device_registries
            where customer_id = $1
              ${activeSql}
            order by created_at desc
            limit 1000
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_branches': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(req, res, 'customerId zorunludur.');
        const showPassive = parseBoolean(req.query.showPassive, true);
        const values = [customerId];
        let activeSql = '';
        if (!showPassive) {
          values.push(true);
          activeSql = `and is_active = $${values.length}`;
        }
        const result = await query(
          `
            select id,name,city,address,phone,location_lat,location_lng,is_active,created_at
            from public.branches
            where customer_id = $1
              ${activeSql}
            order by created_at desc
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_work_orders': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(req, res, 'customerId zorunludur.');
        await ensureWorkOrdersPaymentRequiredColumn();
        await ensureWorkOrdersStatusCheckConstraint();
        const showPassive = parseBoolean(req.query.showPassive, true);
        const values = [customerId];
        let activeSql = '';
        if (!showPassive) {
          values.push(true);
          activeSql = `and is_active = $${values.length}`;
        }

        if (user.role !== 'admin') {
          values.push(user.id);
          activeSql += ` and assigned_to = $${values.length}`;
        }

        const result = await query(
          `
            select
              w.id,
              w.title,
              w.customer_id,
              c.name as customer_name,
              w.description,
              w.address,
              w.city,
              w.status,
              w.payment_required,
              w.branch_id,
              b.name as branch_name,
              w.assigned_to,
              u.full_name as assigned_personnel_name,
              w.scheduled_date,
              w.created_at,
              w.closed_at,
              w.work_order_type_id,
              wt.name as work_order_type_name,
              w.contact_phone,
              w.location_link,
              w.close_notes,
              w.sort_order,
              w.is_active,
              '[]'::json as payments
            from public.work_orders
            w
            left join public.customers c on c.id = w.customer_id
            left join public.branches b on b.id = w.branch_id
            left join public.users u on u.id = w.assigned_to
            left join public.work_order_types wt on wt.id = w.work_order_type_id
            where w.customer_id = $1
              ${activeSql}
            order by w.created_at desc
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'work_order_detail': {
        if (!requirePage(req, user, 'is_emirleri', res)) return;
        await ensureWorkOrderSignaturesTable();
        await ensureWorkOrdersPaymentRequiredColumn();
        await ensureWorkOrdersStatusCheckConstraint();
        const workOrderId = String(req.query.workOrderId || '').trim();
        if (!workOrderId) return ok(req, res, { item: null });

        const result = await query(
          `
            select
              w.id,
              w.title,
              w.description,
              w.address,
              w.city,
              w.status,
              w.is_active,
              w.payment_required,
              w.customer_id,
              w.branch_id,
              w.assigned_to,
              w.scheduled_date,
              w.created_at,
              w.closed_at,
              w.work_order_type_id,
              w.contact_phone,
              w.location_link,
              w.close_notes,
              w.sort_order,
              c.name as customer_name,
              b.name as branch_name,
              u.full_name as assigned_personnel_name,
              wt.name as work_order_type_name,
              coalesce(
                (
                  select json_agg(
                    json_build_object(
                      'amount', p.amount,
                      'currency', p.currency,
                      'paid_at', p.paid_at,
                      'description', p.description,
                      'payment_method', p.payment_method,
                      'is_active', p.is_active
                    )
                    order by p.paid_at asc nulls last, p.created_at asc
                  )
                  from public.payments p
                  where p.work_order_id = w.id and p.is_active = true
                ),
                '[]'::json
              ) as payments,
              s.customer_signature_data_url,
              s.personnel_signature_data_url
            from public.work_orders w
            left join public.customers c on c.id = w.customer_id
            left join public.branches b on b.id = w.branch_id
            left join public.users u on u.id = w.assigned_to
            left join public.work_order_types wt on wt.id = w.work_order_type_id
            left join public.work_order_signatures s on s.work_order_id = w.id
            where w.id = $1
            limit 1
          `,
          [workOrderId],
        );

        return ok(req, res, { item: result.rows[0] || null });
      }

      case 'customers_for_transfer': {
        const result = await query(
          `select id,name,is_active from public.customers order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'service_list': {
        const showPassive = parseBoolean(req.query.showPassive, false);
        await ensureServiceRecordsColumns();
        await ensureServiceRecordsExtendedColumns();
        await ensureServiceRecordsStatusCheckConstraint();
        await ensureServiceFaultTypesTable();
        const page = parseInteger(req.query.page, 1, { min: 1, max: 1000000 });
        const pageSize = parseInteger(req.query.pageSize, 50, { min: 10, max: 200 });
        const offset = (page - 1) * pageSize;

        const status = String(req.query.status || '').trim();
        const priority = String(req.query.priority || '').trim();
        const technicianId = String(req.query.technicianId || '').trim();
        const startDate = String(req.query.startDate || '').trim();
        const endDate = String(req.query.endDate || '').trim();
        const search = String(req.query.search || '').trim();

        const values = [];
        let whereSql = 'where true';
        if (!showPassive) {
          values.push(true);
          whereSql += ` and s.is_active = $${values.length}`;
        }
        if (status && status !== 'all') {
          values.push(status);
          whereSql += ` and s.status = $${values.length}`;
        }
        if (priority && priority !== 'all') {
          values.push(priority);
          whereSql += ` and s.priority = $${values.length}`;
        }
        if (technicianId && technicianId !== 'all') {
          values.push(technicianId);
          whereSql += ` and s.technician_id = $${values.length}`;
        }
        if (startDate) {
          values.push(startDate);
          whereSql += ` and s.created_at >= $${values.length}::timestamptz`;
        }
        if (endDate) {
          values.push(endDate);
          whereSql += ` and s.created_at <= $${values.length}::timestamptz`;
        }
        if (search) {
          values.push(`%${search}%`);
          const idx = values.length;
          const normParam = `translate(replace(replace(replace(lower($${idx}), 'i̇', 'i'), 'ı', 'i'), 'İ', 'i'), 'çğıöşü', 'cgiosu')`;
          const normCol = (col) =>
            `translate(replace(replace(replace(lower(coalesce(${col},'')), 'i̇', 'i'), 'ı', 'i'), 'İ', 'i'), 'çğıöşü', 'cgiosu')`;
          whereSql += ` and (
            ${normCol('c.name')} like ${normParam}
            or ${normCol('s.title')} like ${normParam}
            or ${normCol('s.registry_number')} like ${normParam}
            or ${normCol('s.device_serial')} like ${normParam}
            or cast(s.service_no as text) ilike $${idx}
          )`;
        }

        const countResult = await query(
          `
            select count(*)::int as total
            from public.service_records s
            left join public.customers c on c.id = s.customer_id
            ${whereSql}
          `,
          values,
        );
        const totalCount = countResult.rows[0]?.total ?? 0;

        const result = await query(
          `
            select
              s.id,
              s.service_no,
              s.title,
              s.status,
              s.priority,
              s.created_at,
              s.appointment_at,
              s.customer_id,
              c.name as customer_name,
              s.registry_number,
              s.fault_type_id,
              ft.name as fault_type_name,
              s.fault_description,
              s.device_brand,
              s.device_model,
              s.device_serial,
              s.technician_id,
              u.full_name as technician_name,
              s.accessories_received,
              s.accessory_type_ids,
              s.total_amount,
              s.currency
            from public.service_records s
            left join public.customers c on c.id = s.customer_id
            left join public.service_fault_types ft on ft.id = s.fault_type_id
            left join public.users u on u.id = s.technician_id
            ${whereSql}
            order by s.created_at desc
            limit ${pageSize}
            offset ${offset}
          `,
          values,
        );

        return ok(req, res, { items: result.rows, totalCount, page, pageSize });
      }

      case 'service_detail': {
        const id = String(req.query.serviceId || '').trim();
        if (!id) return badRequest(req, res, 'serviceId zorunludur.');
        await ensureServiceRecordsColumns();
        await ensureServiceRecordsExtendedColumns();
        await ensureServiceRecordsStatusCheckConstraint();
        await ensureServiceFaultTypesTable();
        const result = await query(
          `
            select
              s.id,
              s.service_no,
              s.title,
              s.status,
              s.priority,
              s.created_at,
              s.appointment_at,
              s.is_active,
              s.notes,
              s.registry_number,
              s.fault_type_id,
              ft.name as fault_type_name,
              s.fault_description,
              s.device_brand,
              s.device_model,
              s.device_serial,
              s.technician_id,
              u.full_name as technician_name,
              s.accessories_received,
              s.accessory_type_ids,
              s.device_images,
              s.intake_customer_signature_data_url,
              s.intake_personnel_signature_data_url,
              s.delivery_customer_signature_data_url,
              s.delivery_personnel_signature_data_url,
              s.currency,
              s.total_amount,
              s.steps,
              s.parts,
              s.labor,
              s.customer_id,
              s.work_order_id,
              json_build_object('name', c.name, 'email', c.email) as customers
            from public.service_records s
            left join public.customers c on c.id = s.customer_id
            left join public.service_fault_types ft on ft.id = s.fault_type_id
            left join public.users u on u.id = s.technician_id
            where s.id = $1
            limit 1
          `,
          [id],
        );
        return ok(req, res, result.rows[0] || null);
      }

      case 'service_activity': {
        const id = String(req.query.serviceId || '').trim();
        if (!id) return badRequest(req, res, 'serviceId zorunludur.');
        await ensureServiceActivityLogsTable();
        const result = await query(
          `
            select
              l.id,
              l.type,
              l.message,
              l.meta,
              l.created_at,
              l.created_by,
              u.full_name as created_by_name
            from public.service_activity_logs l
            left join public.users u on u.id = l.created_by
            where l.service_id = $1
            order by l.created_at desc
            limit 200
          `,
          [id],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'service_customer_device_registries': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return ok(req, res, { items: [] });
        await ensureDeviceRegistriesTable();
        const result = await query(
          `
            select
              id,
              registry_number,
              model,
              is_active,
              created_at
            from public.device_registries
            where customer_id = $1
              and coalesce(is_active, true) = true
            order by created_at desc
            limit 1000
          `,
          [customerId],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_device_by_serial': {
        if (!requireAnyPage(req, user, ['servis'], res)) return;
        const serial = String(req.query.serial || '').trim();
        if (!serial) return ok(req, res, {});
        const result = await query(
          `select id,customer_id,serial_no,is_active from public.customer_devices where serial_no = $1 limit 1`,
          [serial],
        );
        return ok(req, res, result.rows[0] || {});
      }

      case 'definition_device_brands': {
        const result = await query(
          `select id,name,is_active,created_at from public.device_brands order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_device_models': {
        const result = await query(
          `
            select
              m.id,
              m.name,
              m.is_active,
              m.brand_id,
              b.name as brand_name
            from public.device_models m
            left join public.device_brands b on b.id = m.brand_id
            order by m.name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_service_fault_types': {
        await ensureServiceFaultTypesTable();
        const result = await query(
          `
            select id,name,sort_order,is_active,created_at
            from public.service_fault_types
            where is_active = true
            order by sort_order asc, name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_service_accessory_types': {
        await ensureServiceAccessoryTypesTable();
        const result = await query(
          `
            select id,name,sort_order,is_active,created_at
            from public.service_accessory_types
            where is_active = true
            order by sort_order asc, name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_work_order_types': {
        const result = await query(
          `select * from public.work_order_types where is_active = true order by sort_order asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_work_order_close_notes': {
        await ensureWorkOrderCloseNotesTable();
        const result = await query(
          `select id,name,is_active,sort_order,created_at from public.work_order_close_notes where is_active = true order by sort_order asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_tax_rates': {
        await query(`
          insert into public.tax_rates (name, rate, is_default, sort_order)
          select 'KDV %0', 0, false, 0
          where not exists (select 1 from public.tax_rates where rate = 0)
        `).catch(() => {});
        await query(`
          insert into public.tax_rates (name, rate, is_default, sort_order)
          select 'KDV %1', 1, false, 1
          where not exists (select 1 from public.tax_rates where rate = 1)
        `).catch(() => {});
        await query(`
          insert into public.tax_rates (name, rate, is_default, sort_order)
          select 'KDV %5', 5, false, 5
          where not exists (select 1 from public.tax_rates where rate = 5)
        `).catch(() => {});
        await query(`
          insert into public.tax_rates (name, rate, is_default, sort_order)
          select 'KDV %10', 10, false, 10
          where not exists (select 1 from public.tax_rates where rate = 10)
        `).catch(() => {});
        await query(`
          insert into public.tax_rates (name, rate, is_default, sort_order)
          select 'KDV %16', 16, false, 16
          where not exists (select 1 from public.tax_rates where rate = 16)
        `).catch(() => {});
        await query(`
          insert into public.tax_rates (name, rate, is_default, sort_order)
          select 'KDV %18', 18, false, 18
          where not exists (select 1 from public.tax_rates where rate = 18)
        `).catch(() => {});
        await query(`
          insert into public.tax_rates (name, rate, is_default, sort_order)
          select 'KDV %20', 20, true, 20
          where not exists (select 1 from public.tax_rates where rate = 20)
        `).catch(() => {});
        const result = await query(`
          with ranked as (
            select
              id,
              case
                when rate in (0, 1, 5, 10, 16, 18, 20)
                  then 'KDV %' || trim(to_char(rate, 'FM999999990.##'))
                else coalesce(nullif(btrim(name), ''), 'KDV %' || trim(to_char(rate, 'FM999999990.##')))
              end as name,
              rate::double precision as rate,
              is_default,
              is_active,
              sort_order,
              created_at,
              row_number() over (
                partition by rate
                order by is_default desc, is_active desc, sort_order asc, created_at asc, id asc
              ) as rn
            from public.tax_rates
            where is_active = true
          )
          select id, name, rate, is_default, is_active, sort_order, created_at
          from ranked
          where rn = 1
          order by rate asc, sort_order asc
        `);
        return ok(req, res, { items: result.rows });
      }

      case 'definition_region_colors': {
        await ensureRegionColorsTable();
        const result = await query(
          `
            select
              region_key,
              label,
              bg_color,
              border_color,
              sort_order,
              is_active
            from public.region_colors
            where is_active = true
            order by sort_order asc, label asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_cities': {
        const result = await query(
          `select id,name,code,is_active,created_at from public.cities where is_active = true order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_fiscal_symbols': {
        const result = await query(
          `select id,name,code,is_active,created_at from public.fiscal_symbols where is_active = true order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_business_activity_types': {
        await ensureBusinessActivityTypesTable();
        const result = await query(
          `select id,name,is_active,created_at from public.business_activity_types order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'definition_software_companies': {
        await ensureSoftwareCompaniesTable();
        const result = await query(
          `select id,name,is_active,created_at from public.software_companies order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'serial_tracking': {
        await ensureSerialTrackingTable();
        const result = await query(
          `
            select
              id,
              product_name,
              serial_number,
              is_active,
              created_by,
              created_at,
              updated_at
            from public.serial_tracking
            order by created_at desc
            limit 1000
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'serial_tracking_lookup': {
        await ensureSerialTrackingTable();
        const serial =
          (req.query && typeof req.query.serial === 'string'
            ? req.query.serial
            : String(req.query?.serial || '')).trim();
        if (!serial) return ok(req, res, { item: null });
        const result = await query(
          `
            select
              id,
              product_name,
              serial_number,
              is_active,
              created_by,
              created_at,
              updated_at
            from public.serial_tracking
            where upper(btrim(serial_number)) = upper(btrim($1))
            limit 1
          `,
          [serial],
        );
        return ok(req, res, { item: result.rows[0] || null });
      }

      case 'work_order_payments': {
        const from = String(req.query.from || '').trim();
        const to = String(req.query.to || '').trim();

        const values = [];
        const conditions = ['p.is_active = true'];
        if (from) {
          values.push(from);
          conditions.push(`p.paid_at::date >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(`p.paid_at::date <= $${values.length}::date`);
        }
        const whereSql = `where ${conditions.join(' and ')}`;

        const result = await query(
          `
            select
              p.id,
              p.work_order_id,
              w.title as work_order_title,
              p.customer_id,
              c.name as customer_name,
              p.amount,
              p.currency,
              p.exchange_rate,
              p.description,
              p.payment_method,
              p.paid_at,
              p.is_active,
              p.created_at
            from public.payments p
            left join public.work_orders w on w.id = p.work_order_id
            left join public.customers c on c.id = p.customer_id
            ${whereSql}
            order by p.paid_at desc nulls last, p.created_at desc
            limit 2000
          `,
          values,
        );

        return ok(req, res, { items: result.rows });
      }

      case 'application_form_print_settings': {
        const result = await query(
          `select * from public.application_form_settings where id = 'default' limit 1`,
        );
        return ok(req, res, result.rows[0] || null);
      }

      case 'scrap_form_print_settings': {
        const result = await query(
          `select * from public.scrap_form_settings where id = 'default' limit 1`,
        );
        return ok(req, res, result.rows[0] || null);
      }

      case 'transfer_form_print_settings': {
        const result = await query(
          `select * from public.transfer_form_settings where id = 'default' limit 1`,
        );
        return ok(req, res, result.rows[0] || null);
      }

      case 'form_application_customers': {
        const result = await query(
          `
            select
              id,
              name,
              vkn,
              tckn_ms,
              email,
              phone_1,
              city,
              address,
              director_name,
              is_active
            from public.customers
            order by name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_customer_by_vkn': {
        const digits = String(req.query.vkn || '').replace(/\D/g, '');
        if (!digits) return badRequest(req, res, 'VKN zorunludur.');
        const result = await query(
          `
            select
              id,
              name,
              vkn,
              tckn_ms,
              email,
              phone_1,
              city,
              address,
              director_name,
              is_active
            from public.customers
            where regexp_replace(coalesce(vkn, ''), '\\D', '', 'g') = $1
            order by created_at desc nulls last
            limit 1
          `,
          [digits],
        );
        return ok(req, res, { item: result.rows[0] || null });
      }

      case 'form_customers_bulk': {
        const idsRaw = String(req.query.ids || '').trim();
        if (!idsRaw) return ok(req, res, { items: [] });
        const ids = idsRaw
          .split(',')
          .map((id) => id.trim())
          .filter((id) => id.length > 0)
          .slice(0, 500);
        if (!ids.length) return ok(req, res, { items: [] });

        const result = await query(
          `
            select
              id,
              vkn,
              tckn_ms,
              phone_1,
              phone_2,
              phone_3
            from public.customers
            where id::text = any($1::text[])
          `,
          [ids],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_stock_products': {
        const result = await query(
          `
            select id,code,name
            from public.products
            where is_active = true
            order by name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_application_list': {
        await ensureApplicationFormsApprovalColumns();
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = 'where true';
        if (!showPassive) {
          values.push(true);
          whereSql += ` and is_active = $${values.length}`;
        }
        if (isBankAdminLikeUser(user)) {
          whereSql += `
            and created_by in (
              select id
              from public.users
              where
                role = 'bank'
                or (
                  role = 'personel'
                  and coalesce(page_permissions, '{}'::text[]) = array['formlar']::text[]
                  and (
                    coalesce(action_permissions, '{}'::text[]) = '{}'::text[]
                    or 'banka_admin' = any(coalesce(action_permissions, '{}'::text[]))
                  )
                )
            )
          `;
        } else if (isBankLikeUser(user)) {
          values.push(user.auth_user_id || user.id);
          whereSql += ` and created_by = $${values.length}`;
        }
        const result = await query(
          `
            select
              id,
              application_date,
              customer_id,
              customer_name,
              customer_tckn_ms,
              work_address,
              tax_office_city_name,
              document_type,
              file_registry_number,
              director,
              brand_name,
              model_name,
              fiscal_symbol_name,
              stock_product_id,
              stock_product_name,
              stock_registry_number,
              accounting_office,
              okc_start_date,
              business_activity_name,
              invoice_number,
              customer_phone,
              customer_email,
              taxpayer_registration_document_name,
              taxpayer_registration_document_mime_type,
              taxpayer_registration_document_data,
              approval_document_name,
              approval_document_mime_type,
              approval_document_storage_bucket,
              approval_document_storage_path,
              approval_document_url,
              approval_document_uploaded_at,
              coalesce(approval_status, 'pending') as approval_status,
              approved_at,
              approved_by,
              created_by,
              is_active,
              created_at
            from public.application_forms
            ${whereSql}
            order by created_at desc
            limit 1200
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'application_form_logs': {
        if (!requireAnyPage(req, user, ['formlar'], res)) return;
        await ensureApplicationFormActivityLogsTable();
        const formId = String(req.query.formId || '').trim();
        if (!formId) return badRequest(req, res, 'formId zorunludur.');

        const result = await query(
          `
            select
              id,
              application_form_id,
              action,
              actor_id,
              actor_name,
              changes,
              old_values,
              new_values,
              created_at
            from public.application_form_activity_logs
            where application_form_id = $1
            order by created_at desc
            limit 200
          `,
          [formId],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_scrap_customers': {
        const result = await query(
          `
            select
              c.id,
              c.name,
              c.vkn,
              c.city,
              c.address,
              c.is_active,
              coalesce(
                (
                  select json_agg(json_build_object('address', b.address))
                  from public.branches b
                  where b.customer_id = c.id
                ),
                '[]'::json
              ) as branches
            from public.customers c
            order by c.name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_scrap_list': {
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = 'where true';
        if (!showPassive) {
          values.push(true);
          whereSql += ` and is_active = $${values.length}`;
        }
        const result = await query(
          `
            select
              id,
              form_date,
              row_number,
              customer_id,
              customer_name,
              customer_address,
              customer_tax_office_and_number,
              device_brand_model_registry,
              okc_start_date,
              last_used_date,
              z_report_count,
              total_vat_collection,
              total_collection,
              intervention_purpose,
              other_findings,
              is_active,
              created_at
            from public.scrap_forms
            ${whereSql}
            order by created_at desc
            limit 500
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_fault_list': {
        if (!requirePage(req, user, 'formlar', res)) return;
        await ensureFaultFormsTable();
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = 'where true';
        if (!showPassive) {
          values.push(true);
          whereSql += ` and is_active = $${values.length}`;
        }
        const result = await query(
          `
            select
              id,
              form_date,
              customer_id,
              customer_name,
              customer_address,
              customer_tax_office,
              customer_vkn,
              device_brand_model,
              company_code_and_registry,
              okc_approval_date_and_number,
              fault_date_time_text,
              fault_description,
              last_z_report_date_and_number,
              last_z_report_date,
              last_z_report_no,
              total_revenue,
              total_vat,
              is_active,
              created_at
            from public.fault_forms
            ${whereSql}
            order by created_at desc
            limit 800
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_transfer_customers': {
        const result = await query(
          `
            select
              c.id,
              c.name,
              c.vkn,
              c.city,
              c.address,
              c.is_active,
              coalesce(
                (
                  select json_agg(json_build_object('address', b.address))
                  from public.branches b
                  where b.customer_id = c.id
                ),
                '[]'::json
              ) as branches
            from public.customers c
            order by c.name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'form_transfer_list': {
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = 'where true';
        if (!showPassive) {
          values.push(true);
          whereSql += ` and is_active = $${values.length}`;
        }
        const result = await query(
          `
            select
              id,
              row_number,
              transferor_name,
              transferor_address,
              transferor_tax_office_and_registry,
              transferor_approval_date_no,
              transferee_name,
              transferee_address,
              transferee_tax_office_and_registry,
              transferee_approval_date_no,
              total_sales_receipt,
              vat_collected,
              last_receipt_date_no,
              z_report_count,
              other_device_info,
              brand_model,
              device_serial_no,
              fiscal_symbol_company_code,
              department_count,
              transfer_date,
              transfer_reason,
              is_active,
              created_at
            from public.transfer_forms
            ${whereSql}
            order by created_at desc
            limit 500
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'personnel_users': {
        const result = await query(
          `
            select
              id,
              full_name,
              role,
              email,
              coalesce(page_permissions, '{}'::text[]) as page_permissions,
              coalesce(action_permissions, '{}'::text[]) as action_permissions,
              created_at
            from public.users
            order by created_at desc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'invoice_items_queue': {
        if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) return;
        const okTable = await ensureInvoiceItemsTable();
        if (!okTable) return ok(req, res, { items: [] });
        const cols = await getTableColumns('invoice_items');
        const has = (c) => cols.includes(c);

        try {
          await query(
            `
              insert into public.invoice_items (
                customer_id,
                item_type,
                source_table,
                source_id,
                description,
                currency,
                status,
                is_active,
                created_at
              )
              select
                l.customer_id,
                'line_renewal'::text,
                'lines'::text,
                l.id,
                (
                  'Hat Yenileme - ' ||
                  coalesce(c.name, '') ||
                  case when coalesce(l.number, '') = '' then '' else (' / ' || l.number) end ||
                  case
                    when l.expires_at is null then ''
                    else (' (Bitiş: ' || to_char(l.expires_at::date, 'DD.MM.YYYY') || ')')
                  end
                )::text,
                'TRY'::text,
                'pending'::text,
                true,
                now()
              from public.lines l
              left join public.customers c on c.id = l.customer_id
              where l.is_active = true
                and l.expires_at is not null
                and l.expires_at >= now()
                and l.expires_at <= now() + interval '30 days'
                and not exists (
                  select 1
                  from public.invoice_items ii
                  where ii.source_table = 'lines'
                    and ii.source_id = l.id
                    and coalesce(ii.item_type::text, '') = 'line_renewal'
                    and coalesce(ii.status::text, 'pending') = 'pending'
                    and coalesce(ii.is_active, true) = true
                )
            `,
          );
        } catch (_) {}

        try {
          await query(
            `
              insert into public.invoice_items (
                customer_id,
                item_type,
                source_table,
                source_id,
                description,
                currency,
                status,
                is_active,
                created_at
              )
              select
                li.customer_id,
                'gmp3_renewal'::text,
                'licenses'::text,
                li.id,
                (
                  'GMP3 Yenileme - ' ||
                  coalesce(c.name, '') ||
                  case when coalesce(li.name, '') = '' then '' else (' / ' || li.name) end ||
                  case
                    when li.expires_at is null then ''
                    else (' (Bitiş: ' || to_char(li.expires_at::date, 'DD.MM.YYYY') || ')')
                  end
                )::text,
                'TRY'::text,
                'pending'::text,
                true,
                now()
              from public.licenses li
              left join public.customers c on c.id = li.customer_id
              where li.is_active = true
                and coalesce(li.license_type::text, '') = 'gmp3'
                and li.expires_at is not null
                and li.expires_at >= now()
                and li.expires_at <= now() + interval '30 days'
                and not exists (
                  select 1
                  from public.invoice_items ii
                  where ii.source_table = 'licenses'
                    and ii.source_id = li.id
                    and coalesce(ii.item_type::text, '') = 'gmp3_renewal'
                    and coalesce(ii.status::text, 'pending') = 'pending'
                    and coalesce(ii.is_active, true) = true
                )
            `,
          );
        } catch (_) {}

        const customerIdSql = has('customer_id')
          ? 'ii.customer_id'
          : 'null::uuid as customer_id';
        const itemTypeSql = has('item_type')
          ? `coalesce(ii.item_type::text, '') as item_type`
          : `''::text as item_type`;
        const descriptionSql = has('description')
          ? 'ii.description'
          : `''::text as description`;
        const amountSql = has('amount')
          ? 'ii.amount'
          : has('line_total')
            ? 'ii.line_total as amount'
            : 'null::numeric as amount';
        const currencySql = has('currency')
          ? 'ii.currency'
          : `'TRY'::text as currency`;
        const statusSql = has('status')
          ? 'ii.status'
          : `'pending'::text as status`;
        const isActiveSql = has('is_active')
          ? 'ii.is_active'
          : 'true::boolean as is_active';
        const createdAtSql = has('created_at')
          ? 'ii.created_at'
          : 'now()::timestamptz as created_at';

        const joinCustomerSql = has('customer_id')
          ? 'left join public.customers c on c.id = ii.customer_id'
          : 'left join public.customers c on false';
        const customerLabelSql = has('customer_id')
          ? 'c.name as customer_label'
          : 'null::text as customer_label';

        const result = await query(
          `
            select
              ii.id,
              ${customerIdSql},
              ${itemTypeSql},
              ${descriptionSql},
              ${amountSql},
              ${currencySql},
              ${statusSql},
              ${isActiveSql},
              ${customerLabelSql},
              ${createdAtSql}
            from public.invoice_items ii
            ${joinCustomerSql}
            order by ${has('created_at') ? 'ii.created_at' : 'ii.id'} desc
            limit 600
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'invoices_list': {
        if (!requireAnyPage(req, user, ['faturalama'], res)) return;
        const invoiceType = String(req.query.invoiceType || '').trim();
        const status = String(req.query.status || '').trim();
        const customerId = String(req.query.customerId || '').trim();
        const startDate = String(req.query.startDate || '').trim();
        const endDate = String(req.query.endDate || '').trim();
        const includePassive = parseBoolean(req.query.includePassive, false);

        const values = [];
        let whereSql = 'where true';
        if (!includePassive) {
          values.push(true);
          whereSql += ` and i.is_active = $${values.length}`;
        }
        if (invoiceType) {
          values.push(invoiceType);
          whereSql += ` and i.invoice_type = $${values.length}`;
        }
        if (status) {
          const statuses = status
            .split(',')
            .map((item) => item.trim())
            .filter(Boolean);
          if (statuses.length > 1) {
            values.push(statuses);
            whereSql += ` and i.status = any($${values.length}::text[])`;
          } else {
            values.push(status);
            whereSql += ` and i.status = $${values.length}`;
          }
        }
        if (customerId) {
          values.push(customerId);
          whereSql += ` and i.customer_id = $${values.length}`;
        }
        if (startDate) {
          values.push(startDate);
          whereSql += ` and i.invoice_date >= $${values.length}::date`;
        }
        if (endDate) {
          values.push(endDate);
          whereSql += ` and i.invoice_date <= $${values.length}::date`;
        }

        const result = await query(
          `
            with filtered_invoices as (
              select i.*
              from public.invoices i
              ${whereSql}
              order by i.invoice_date desc
              limit 800
            ),
            item_totals as (
              select
                ii.invoice_id,
                coalesce(sum(ii.unit_price * ii.quantity), 0) as subtotal,
                coalesce(sum(
                  case
                    when ii.discount_amount >= (ii.unit_price * ii.quantity) - 0.01 then 0
                    else ii.discount_amount
                  end
                ), 0) as discount_total,
                coalesce(sum(
                  case
                    when ii.tax_amount <> 0 then ii.tax_amount
                    else greatest(
                      0,
                      ((ii.unit_price * ii.quantity) -
                        case
                          when ii.discount_amount >= (ii.unit_price * ii.quantity) - 0.01 then 0
                          else ii.discount_amount
                        end
                      ) * (ii.tax_rate / 100)
                    )
                  end
                ), 0) as tax_total,
                coalesce(sum(
                  case
                    when ii.line_total <> 0 then ii.line_total
                    else greatest(
                      0,
                      ((ii.unit_price * ii.quantity) -
                        case
                          when ii.discount_amount >= (ii.unit_price * ii.quantity) - 0.01 then 0
                          else ii.discount_amount
                        end
                      ) * (1 + (ii.tax_rate / 100))
                    )
                  end
                ), 0) as grand_total
              from public.invoice_items ii
              join filtered_invoices fi on fi.id = ii.invoice_id
              group by ii.invoice_id
            )
            select
              fi.*,
              case
                when coalesce(fi.subtotal, 0) = 0 and coalesce(item_totals.subtotal, 0) <> 0
                  then item_totals.subtotal
                else fi.subtotal
              end as effective_subtotal,
              case
                when coalesce(fi.tax_total, 0) = 0 and coalesce(item_totals.tax_total, 0) <> 0
                  then item_totals.tax_total
                else fi.tax_total
              end as effective_tax_total,
              case
                when coalesce(fi.discount_total, 0) = 0 and coalesce(item_totals.discount_total, 0) <> 0
                  then item_totals.discount_total
                else fi.discount_total
              end as effective_discount_total,
              case
                when coalesce(fi.grand_total, 0) = 0 and coalesce(item_totals.grand_total, 0) <> 0
                  then item_totals.grand_total
                when coalesce(fi.grand_total, 0) = 0 and coalesce(fi.paid_amount, 0) <> 0
                  then fi.paid_amount
                else fi.grand_total
              end as effective_grand_total,
              case
                when coalesce(fi.grand_total, 0) = 0
                  and fi.status = 'partial'
                  then 'open'
                else fi.status
              end as effective_status,
              json_build_object('name', c.name) as customers
            from filtered_invoices fi
            left join public.customers c on c.id = fi.customer_id
            left join item_totals on item_totals.invoice_id = fi.id
            order by fi.invoice_date desc
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_open_invoices': {
        if (!requireAnyPage(req, user, ['faturalama', 'e_fatura', 'musteriler'], res)) return;
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(req, res, 'customerId zorunludur.');
        const result = await query(
          `
            select
              i.*,
              case
                when coalesce(i.grand_total, 0) = 0 and coalesce(item_totals.grand_total, 0) <> 0
                  then item_totals.grand_total
                when coalesce(i.grand_total, 0) = 0 and coalesce(i.paid_amount, 0) <> 0
                  then i.paid_amount
                else i.grand_total
              end as effective_grand_total,
              case
                when coalesce(i.grand_total, 0) = 0
                  and i.status = 'partial'
                  then 'open'
                else i.status
              end as effective_status,
              json_build_object('name', c.name) as customers
            from public.invoices i
            left join public.customers c on c.id = i.customer_id
            left join lateral (
              select coalesce(sum(
                case
                  when ii.line_total <> 0 then ii.line_total
                  else greatest(
                    0,
                    ((ii.unit_price * ii.quantity) -
                      case
                        when ii.discount_amount >= (ii.unit_price * ii.quantity) - 0.01 then 0
                        else ii.discount_amount
                      end
                    ) * (1 + (ii.tax_rate / 100))
                  )
                end
              ), 0) as grand_total
              from public.invoice_items ii
              where ii.invoice_id = i.id
            ) item_totals on true
            where i.customer_id = $1
              and i.is_active = true
              and i.status in ('open','partial')
            order by i.invoice_date desc
          `,
          [customerId],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'invoice_detail': {
        if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) return;
        const id = String(req.query.invoiceId || '').trim();
        if (!id) return badRequest(req, res, 'invoiceId zorunludur.');
        const result = await query(
          `
            select
              i.*,
              json_build_object('name', c.name) as customers,
              coalesce(
                (
                  select json_agg(ii order by ii.sort_order asc)
                  from public.invoice_items ii
                  where ii.invoice_id = i.id
                ),
                '[]'::json
              ) as invoice_items
            from public.invoices i
            left join public.customers c on c.id = i.customer_id
            where i.id = $1
            limit 1
          `,
          [id],
        );
        return ok(req, res, result.rows[0] || null);
      }

      case 'account_balances': {
        if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) return;
        const result = await query(
          `select * from public.account_balances order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'transactions_list': {
        if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) return;
        const customerId = String(req.query.customerId || '').trim();
        const invoiceId = String(req.query.invoiceId || '').trim();
        const transactionType = String(req.query.transactionType || '').trim();
        const startDate = String(req.query.startDate || '').trim();
        const endDate = String(req.query.endDate || '').trim();
        const includePassive = parseBoolean(req.query.includePassive, false);

        const values = [];
        let whereSql = 'where true';
        if (!includePassive) {
          values.push(true);
          whereSql += ` and t.is_active = $${values.length}`;
        }
        if (customerId) {
          values.push(customerId);
          whereSql += ` and t.customer_id = $${values.length}`;
        }
        if (invoiceId) {
          values.push(invoiceId);
          whereSql += ` and t.invoice_id = $${values.length}`;
        }
        if (transactionType) {
          values.push(transactionType);
          whereSql += ` and t.transaction_type = $${values.length}`;
        }
        if (startDate) {
          values.push(startDate);
          whereSql += ` and t.transaction_date >= $${values.length}::date`;
        }
        if (endDate) {
          values.push(endDate);
          whereSql += ` and t.transaction_date <= $${values.length}::date`;
        }

        const result = await query(
          `
            select
              t.*,
              json_build_object('name', c.name) as customers,
              json_build_object('invoice_number', i.invoice_number) as invoices
            from public.transactions t
            left join public.customers c on c.id = t.customer_id
            left join public.invoices i on i.id = t.invoice_id
            ${whereSql}
            order by t.transaction_date desc, t.created_at desc
            limit 1200
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'finance_accounts': {
        await ensureFinanceTables();
        const includePassive = parseBoolean(req.query.includePassive, false);
        const values = [];
        let whereSql = 'where true';
        if (!includePassive) {
          values.push(true);
          whereSql += ` and a.is_active = $${values.length}`;
        }
        const result = await query(
          `
            select
              a.*,
              coalesce(tx.in_count, 0)::int as in_count,
              coalesce(tx.out_count, 0)::int as out_count
            from public.finance_accounts a
            left join lateral (
              select
                count(*) filter (where direction = 'in' and is_active = true) as in_count,
                count(*) filter (where direction = 'out' and is_active = true) as out_count
              from public.finance_transactions t
              where t.account_id = a.id
            ) tx on true
            ${whereSql}
            order by a.is_active desc, a.account_type asc, a.name asc
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'finance_transactions': {
        await ensureFinanceTables();
        const accountId = String(req.query.accountId || '').trim();
        const customerId = String(req.query.customerId || '').trim();
        const direction = String(req.query.direction || '').trim();
        const transactionType = String(req.query.transactionType || '').trim();
        const startDate = String(req.query.startDate || '').trim();
        const endDate = String(req.query.endDate || '').trim();
        const includePassive = parseBoolean(req.query.includePassive, false);

        const values = [];
        let whereSql = 'where true';
        if (!includePassive) {
          values.push(true);
          whereSql += ` and t.is_active = $${values.length}`;
        }
        if (accountId) {
          values.push(accountId);
          whereSql += ` and t.account_id = $${values.length}`;
        }
        if (customerId) {
          values.push(customerId);
          whereSql += ` and t.customer_id = $${values.length}`;
        }
        if (direction) {
          values.push(direction);
          whereSql += ` and t.direction = $${values.length}`;
        }
        if (transactionType) {
          values.push(transactionType);
          whereSql += ` and t.transaction_type = $${values.length}`;
        }
        if (startDate) {
          values.push(startDate);
          whereSql += ` and t.transaction_date >= $${values.length}::date`;
        }
        if (endDate) {
          values.push(endDate);
          whereSql += ` and t.transaction_date <= $${values.length}::date`;
        }

        const result = await query(
          `
            select
              t.*,
              json_build_object('name', a.name, 'account_type', a.account_type, 'currency', a.currency) as finance_accounts,
              json_build_object('name', c.name, 'vkn', c.vkn) as customers,
              json_build_object('invoice_number', i.invoice_number) as invoices
            from public.finance_transactions t
            left join public.finance_accounts a on a.id = t.account_id
            left join public.customers c on c.id = t.customer_id
            left join public.invoices i on i.id = t.invoice_id
            ${whereSql}
            order by t.transaction_date desc, t.created_at desc
            limit 2000
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'reports_users': {
        if (!requireAnyPage(req, user, ['raporlar'], res)) return;
        const result = await query(
          `select id,full_name,role from public.users order by full_name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'reports_payments': {
        if (!requireAnyPage(req, user, ['raporlar'], res)) return;
        const from = String(req.query.from || '').trim();
        const userId = String(req.query.userId || '').trim();
        const values = [];
        let whereSql = `where p.is_active = true`;
        if (from) {
          values.push(from);
          whereSql += ` and p.paid_at >= $${values.length}::timestamptz`;
        }
        if (userId) {
          values.push(userId);
          whereSql += ` and p.created_by = $${values.length}`;
        }
        const result = await query(
          `
            select
              p.paid_at,
              p.amount,
              p.currency,
              p.payment_method,
              json_build_object('name', c.name) as customers
            from public.payments p
            left join public.customers c on c.id = p.customer_id
            ${whereSql}
            order by p.paid_at asc
            limit 50000
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'reports_work_orders': {
        if (!requireAnyPage(req, user, ['raporlar'], res)) return;
        const from = String(req.query.from || '').trim();
        const userId = String(req.query.userId || '').trim();
        const values = [];
        let whereSql = `where w.is_active = true`;
        if (from) {
          values.push(from);
          whereSql += ` and w.created_at >= $${values.length}::timestamptz`;
        }
        if (userId) {
          values.push(userId);
          whereSql += ` and w.assigned_to = $${values.length}`;
        }
        const result = await query(
          `
            select w.status, w.created_at
            from public.work_orders w
            ${whereSql}
            order by w.created_at asc
            limit 50000
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'invoice_number': {
        if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) return;
        const invoiceType = String(req.query.invoiceType || '').trim();
        if (!invoiceType) return badRequest(req, res, 'invoiceType zorunludur.');
        const result = await query(
          `select public.generate_invoice_number($1) as value`,
          [invoiceType],
        );
        return ok(req, res, { value: result.rows[0]?.value || '' });
      }

      case 'products_list': {
        if (!requireAnyPage(req, user, ['urunler', 'faturalama', 'e_fatura', 'formlar'], res)) return;
        const category = String(req.query.category || '').trim();
        const values = [];
        let whereSql = 'where p.is_active = true';
        if (category) {
          values.push(category);
          whereSql += ` and p.category = $${values.length}`;
        }
        const result = await query(
          `
            select p.*
            from public.products p
            ${whereSql}
            order by p.name asc
            limit 1200
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'stock_levels': {
        if (!requireAnyPage(req, user, ['urunler', 'faturalama', 'e_fatura'], res)) return;
        const result = await query(`select * from public.stock_levels`);
        return ok(req, res, { items: result.rows });
      }

      case 'product_serial_inventory': {
        if (!requireAnyPage(req, user, ['urunler', 'formlar'], res)) return;
        const productId = String(req.query.productId || '').trim();
        const includeConsumed = parseBoolean(req.query.includeConsumed, false);
        const values = [];
        let whereSql = 'where psi.is_active = true';
        if (productId) {
          values.push(productId);
          whereSql += ` and psi.product_id = $${values.length}`;
        }
        if (!includeConsumed) {
          whereSql += ` and psi.consumed_at is null`;
        }
        const result = await query(
          `
            select
              psi.*,
              json_build_object('name', p.name, 'code', p.code) as products
            from public.product_serial_inventory psi
            left join public.products p on p.id = psi.product_id
            ${whereSql}
            order by psi.created_at desc
            limit 2000
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'product_serial_inventory_summary': {
        if (!requireAnyPage(req, user, ['urunler', 'formlar'], res)) return;
        const result = await query(
          `select product_id,total_count,available_count,consumed_count from public.product_serial_inventory_summary`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customers_lookup': {
        const result = await query(
          `select id,name,is_active from public.customers order by name asc`,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customers_basic': {
        if (
          !requireAnyPage(
            user,
            ['musteriler', 'is_emirleri', 'servis', 'faturalama', 'formlar'],
            res,
          )
        )
          return;
        const result = await query(
          `
            select id,name,city,address,is_active
            from public.customers
            where is_active = true
            order by name asc
          `,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'customer_branches': {
        if (!requireAnyPage(req, user, ['musteriler', 'is_emirleri'], res)) return;
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return ok(req, res, { items: [] });
        const result = await query(
          `
            select id,name,is_active
            from public.branches
            where customer_id = $1 and is_active = true
            order by name asc
          `,
          [customerId],
        );
        return ok(req, res, { items: result.rows });
      }

      case 'products_lines': {
        const search = String(req.query.search || '').trim();
        const operator = String(req.query.operator || '').trim();
        const customer = String(req.query.customer || '').trim();
        const endsFrom = String(req.query.endsFrom || '').trim();
        const endsTo = String(req.query.endsTo || '').trim();
        const limitRaw = Number.parseInt(String(req.query.limit || ''), 10);
        const limit = Number.isFinite(limitRaw)
          ? Math.min(Math.max(limitRaw, 1), 5000)
          : 2000;
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = 'where true';

        if (!(user.role === 'admin' && showPassive)) {
          values.push(true);
          whereSql += ` and l.is_active = $${values.length}`;
        }

        if (search) {
          values.push(`%${search}%`);
          whereSql += ` and (
            l.number ilike $${values.length}
            or l.sim_number ilike $${values.length}
            or c.name ilike $${values.length}
            or b.name ilike $${values.length}
          )`;
        }

        if (customer) {
          values.push(`%${customer}%`);
          whereSql += ` and c.name ilike $${values.length}`;
        }

        if (operator === 'turkcell') {
          whereSql += ` and lower(coalesce(l.operator,'')) = 'turkcell'`;
        }
        if (operator === 'telsim') {
          whereSql += ` and lower(coalesce(l.operator,'')) in ('telsim','vodafone')`;
        }

        if (endsFrom) {
          values.push(endsFrom);
          whereSql += ` and coalesce(l.ends_at, l.expires_at) >= $${values.length}`;
        }
        if (endsTo) {
          values.push(endsTo);
          whereSql += ` and coalesce(l.ends_at, l.expires_at) <= $${values.length}`;
        }

        await ensureLinesOperatorColumn();
        const result = await query(
          `
            select
              l.id,
              l.label,
              l.number,
              l.sim_number,
              l.operator,
              l.starts_at,
              l.ends_at,
              l.expires_at,
              l.is_active,
              l.customer_id,
              l.branch_id,
              c.name as customer_name,
              b.name as branch_name
            from public.lines l
            left join public.customers c on c.id = l.customer_id
            left join public.branches b on b.id = l.branch_id
            ${whereSql}
            order by l.ends_at asc nulls last, l.created_at desc
            limit ${limit}
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'line_stock': {
        if (!requireAnyPage(req, user, ['urunler', 'is_emirleri'], res)) return;
        await ensureLineStockTable();

        const search = String(req.query.search || '').trim();
        const status = String(req.query.status || '').trim();
        const operator = String(req.query.operator || '').trim();
        const consumedFrom = String(req.query.consumedFrom || '').trim();
        const consumedTo = String(req.query.consumedTo || '').trim();
        const limitRaw = Number.parseInt(String(req.query.limit || ''), 10);
        const limit = Number.isFinite(limitRaw)
          ? Math.min(Math.max(limitRaw, 1), 5000)
          : 2000;

        const values = [];
        let whereSql = `where true`;

        if (status === 'available') {
          whereSql += ` and ls.is_active = true and ls.consumed_at is null`;
        } else if (status === 'consumed') {
          whereSql += ` and ls.consumed_at is not null`;
        } else if (status === 'passive') {
          whereSql += ` and ls.is_active = false`;
        }

        if (operator) {
          values.push(operator);
          whereSql += ` and lower(coalesce(ls.operator,'')) = lower($${values.length})`;
        }

        if (search) {
          values.push(`%${search}%`);
          whereSql += ` and (
            ls.line_number ilike $${values.length}
            or coalesce(ls.sim_number,'') ilike $${values.length}
            or coalesce(ls.operator,'') ilike $${values.length}
            or coalesce(c.name,'') ilike $${values.length}
          )`;
        }

        if (consumedFrom) {
          values.push(`${consumedFrom}T00:00:00Z`);
          whereSql += ` and ls.consumed_at >= $${values.length}`;
        }
        if (consumedTo) {
          values.push(`${consumedTo}T23:59:59Z`);
          whereSql += ` and ls.consumed_at <= $${values.length}`;
        }

        const result = await query(
          `
            select
              ls.*,
              c.name as consumed_customer_name,
              wo.title as consumed_work_order_title
            from public.line_stock ls
            left join public.customers c on c.id = ls.consumed_customer_id
            left join public.work_orders wo on wo.id = ls.consumed_work_order_id
            ${whereSql}
            order by ls.created_at desc
            limit ${limit}
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'products_licenses': {
        const search = String(req.query.search || '').trim();
        const softwareCompanyId = String(req.query.softwareCompanyId || '').trim();
        const customer = String(req.query.customer || '').trim();
        const endsFrom = String(req.query.endsFrom || '').trim();
        const endsTo = String(req.query.endsTo || '').trim();
        const limitRaw = Number.parseInt(String(req.query.limit || ''), 10);
        const limit = Number.isFinite(limitRaw)
          ? Math.min(Math.max(limitRaw, 1), 5000)
          : 2000;
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = `where true`;

        if (!(user.role === 'admin' && showPassive)) {
          values.push(true);
          whereSql += ` and lic.is_active = $${values.length}`;
        }

        if (search) {
          values.push(`%${search}%`);
          whereSql += ` and (
            lic.name ilike $${values.length}
            or c.name ilike $${values.length}
            or sc.name ilike $${values.length}
          )`;
        }

        if (customer) {
          values.push(`%${customer}%`);
          whereSql += ` and c.name ilike $${values.length}`;
        }

        if (softwareCompanyId) {
          if (softwareCompanyId === 'unknown') {
            whereSql += ` and lic.software_company_id is null`;
          } else {
            values.push(softwareCompanyId);
            whereSql += ` and lic.software_company_id = $${values.length}`;
          }
        }

        if (endsFrom) {
          values.push(endsFrom);
          whereSql += ` and coalesce(lic.ends_at, lic.expires_at) >= $${values.length}`;
        }
        if (endsTo) {
          values.push(endsTo);
          whereSql += ` and coalesce(lic.ends_at, lic.expires_at) <= $${values.length}`;
        }

        await ensureLicensesSoftwareCompanyColumn();
        await ensureLicensesRegistryNumberColumn();
        const result = await query(
          `
            select
              lic.id,
              lic.name,
              lic.license_type,
              lic.software_company_id,
              sc.name as software_company_name,
              lic.registry_number,
              lic.starts_at,
              lic.ends_at,
              lic.expires_at,
              lic.is_active,
              lic.customer_id,
              c.name as customer_name
            from public.licenses lic
            left join public.customers c on c.id = lic.customer_id
            left join public.software_companies sc on sc.id = lic.software_company_id
            ${whereSql}
            order by lic.ends_at asc nulls last, lic.created_at desc
            limit ${limit}
          `,
          values,
        );
        return ok(req, res, { items: result.rows });
      }

      case 'products_licenses_stats': {
        const search = String(req.query.search || '').trim();
        const customer = String(req.query.customer || '').trim();
        const endsFrom = String(req.query.endsFrom || '').trim();
        const endsTo = String(req.query.endsTo || '').trim();
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = `where lic.license_type = 'gmp3'`;

        if (!showPassive) {
          whereSql += ` and lic.is_active = true`;
        }

        if (search) {
          values.push(`%${search}%`);
          whereSql += ` and (
            lic.name ilike $${values.length}
            or c.name ilike $${values.length}
            or sc.name ilike $${values.length}
          )`;
        }

        if (customer) {
          values.push(`%${customer}%`);
          whereSql += ` and c.name ilike $${values.length}`;
        }

        if (endsFrom) {
          values.push(endsFrom);
          whereSql += ` and coalesce(lic.ends_at, lic.expires_at) >= $${values.length}`;
        }
        if (endsTo) {
          values.push(endsTo);
          whereSql += ` and coalesce(lic.ends_at, lic.expires_at) <= $${values.length}`;
        }

        await ensureLicensesSoftwareCompanyColumn();
        await ensureLicensesRegistryNumberColumn();

        const totalResult = await query(
          `
            select count(*)::int as total
            from public.licenses lic
            left join public.customers c on c.id = lic.customer_id
            left join public.software_companies sc on sc.id = lic.software_company_id
            ${whereSql}
          `,
          values,
        );
        const gmp3Total = totalResult.rows?.[0]?.total ?? 0;

        const byCompany = await query(
          `
            select
              sc.name as software_company_name,
              count(*)::int as total
            from public.licenses lic
            left join public.customers c on c.id = lic.customer_id
            left join public.software_companies sc on sc.id = lic.software_company_id
            ${whereSql}
            group by sc.name
            order by total desc, software_company_name asc nulls last
          `,
          values,
        );

        const byCustomer = await query(
          `
            select
              c.name as customer_name,
              count(*)::int as total
            from public.licenses lic
            left join public.customers c on c.id = lic.customer_id
            left join public.software_companies sc on sc.id = lic.software_company_id
            ${whereSql}
            group by c.name
            order by total desc, customer_name asc nulls last
            limit 20
          `,
          values,
        );

        return ok(req, res, {
          gmp3_total: gmp3Total,
          by_company: byCompany.rows,
          by_customer: byCustomer.rows,
        });
      }

      case 'products_customer_totals': {
        const search = String(req.query.search || '').trim();
        const showPassive = parseBoolean(req.query.showPassive, false);
        const limitRaw = Number.parseInt(String(req.query.limit || ''), 10);
        const limit = Number.isFinite(limitRaw)
          ? Math.min(Math.max(limitRaw, 1), 5000)
          : 2000;
        const values = [];

        let whereCustomerSql = `where true`;
        if (search) {
          values.push(`%${search}%`);
          whereCustomerSql += ` and c.name ilike $${values.length}`;
        }

        await ensureLinesOperatorColumn();
        await ensureLicensesSoftwareCompanyColumn();
        await ensureLicensesRegistryNumberColumn();

        const lineWhere = showPassive ? '' : 'where l.is_active = true';
        const gmp3Where = showPassive
          ? `where lic.license_type = 'gmp3'`
          : `where lic.license_type = 'gmp3' and lic.is_active = true`;

        const result = await query(
          `
            with line_counts as (
              select
                l.customer_id,
                count(*)::int as lines_total,
                sum(case when lower(coalesce(l.operator,'')) = 'turkcell' then 1 else 0 end)::int as lines_turkcell,
                sum(case when lower(coalesce(l.operator,'')) in ('telsim','vodafone') then 1 else 0 end)::int as lines_telsim
              from public.lines l
              ${lineWhere}
              group by l.customer_id
            ),
            gmp3_counts as (
              select
                lic.customer_id,
                count(*)::int as gmp3_total
              from public.licenses lic
              ${gmp3Where}
              group by lic.customer_id
            )
            select
              c.id as customer_id,
              c.name as customer_name,
              coalesce(lc.lines_total, 0)::int as lines_total,
              coalesce(lc.lines_turkcell, 0)::int as lines_turkcell,
              coalesce(lc.lines_telsim, 0)::int as lines_telsim,
              coalesce(gc.gmp3_total, 0)::int as gmp3_total
            from public.customers c
            left join line_counts lc on lc.customer_id = c.id
            left join gmp3_counts gc on gc.customer_id = c.id
            ${whereCustomerSql}
              and (coalesce(lc.lines_total, 0) > 0 or coalesce(gc.gmp3_total, 0) > 0)
            order by gmp3_total desc, lines_total desc, customer_name asc
            limit ${limit}
          `,
          values,
        );

        return ok(req, res, { items: result.rows });
      }

      case 'halkbank_exchange_rates': {
        const nowMs = Date.now();
        if (halkbankRatesCache.payload && nowMs - halkbankRatesCache.fetchedAtMs < 60 * 1000) {
          return ok(req, res, halkbankRatesCache.payload);
        }

        const sourceUrl = 'https://kur.doviz.com/halkbank';
        const html = await fetchText(sourceUrl);
        if (!html || html.length < 1000) {
          return serverError(req, res, new Error('Döviz verisi okunamadı.'));
        }

        const usd = parseHalkbankRow(html, 'amerikan-dolari', 'USD');
        const eur = parseHalkbankRow(html, 'euro', 'EUR');
        const gbp = parseHalkbankRow(html, 'sterlin', 'GBP');
        const items = [usd, eur, gbp].filter(Boolean);

        const payload = {
          sourceUrl,
          fetchedAt: new Date().toISOString(),
          items,
        };
        halkbankRatesCache = { fetchedAtMs: nowMs, payload };
        return ok(req, res, payload);
      }

      default:
        return badRequest(req, res, `Bilinmeyen resource: ${resource}`);
    }
  } catch (error) {
    return serverError(req, res, error);
  }
};
