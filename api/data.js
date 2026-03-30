const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
  parseBoolean,
} = require('./_lib/http');

function requirePage(user, pageKey, res) {
  if (!hasPageAccess(user, pageKey)) {
    forbidden(res, 'Erişim yetkiniz yok.');
    return false;
  }
  return true;
}

module.exports = async (req, res) => {
  if (req.method !== 'GET') {
    return methodNotAllowed(res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);

    const resource = String(req.query.resource || '').trim();
    if (!resource) return badRequest(res, 'resource zorunludur.');

    if (
      resource.startsWith('customer') ||
      resource === 'customers_for_transfer' ||
      resource === 'customer_branches' ||
      resource === 'customer_lines' ||
      resource === 'customer_licenses' ||
      resource === 'customer_work_orders'
    ) {
      if (!requirePage(user, 'musteriler', res)) return;
    }
    if (resource.startsWith('service')) {
      if (!requirePage(user, 'servis', res)) return;
    }
    if (resource.startsWith('definition_')) {
      if (!requirePage(user, 'tanimlamalar', res)) return;
    }
    if (resource.startsWith('personnel_')) {
      if (!requirePage(user, 'personel', res)) return;
    }
    if (resource.startsWith('products_') || resource === 'customers_lookup') {
      if (!requirePage(user, 'urunler', res)) return;
    }
    if (
      resource === 'application_form_print_settings' ||
      resource === 'scrap_form_print_settings' ||
      resource === 'transfer_form_print_settings'
    ) {
      if (!requirePage(user, 'formlar', res)) return;
    }
    if (resource.startsWith('form_')) {
      if (!requirePage(user, 'formlar', res)) return;
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
        return ok(res, { items: result.rows });
      }

      case 'customer_detail': {
        const id = String(req.query.customerId || '').trim();
        if (!id) return badRequest(res, 'customerId zorunludur.');
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
        return ok(res, result.rows[0] || null);
      }

      case 'customer_lines': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(res, 'customerId zorunludur.');
        const showPassive = parseBoolean(req.query.showPassive, true);
        const values = [customerId];
        let activeSql = '';
        if (!showPassive) {
          values.push(true);
          activeSql = `and is_active = $${values.length}`;
        }
        const result = await query(
          `
            select id,label,number,sim_number,starts_at,ends_at,expires_at,is_active,created_at
            from public.lines
            where customer_id = $1
              ${activeSql}
            order by created_at desc
          `,
          values,
        );
        return ok(res, { items: result.rows });
      }

      case 'customer_locations': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(res, 'customerId zorunludur.');
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
        return ok(res, { items: result.rows });
      }

      case 'customer_licenses': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(res, 'customerId zorunludur.');
        const showPassive = parseBoolean(req.query.showPassive, true);
        const values = [customerId];
        let activeSql = '';
        if (!showPassive) {
          values.push(true);
          activeSql = `and is_active = $${values.length}`;
        }
        const result = await query(
          `
            select id,name,license_type,starts_at,ends_at,expires_at,is_active,created_at
            from public.licenses
            where customer_id = $1
              ${activeSql}
            order by created_at desc
          `,
          values,
        );
        return ok(res, { items: result.rows });
      }

      case 'customer_branches': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(res, 'customerId zorunludur.');
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
        return ok(res, { items: result.rows });
      }

      case 'customer_work_orders': {
        const customerId = String(req.query.customerId || '').trim();
        if (!customerId) return badRequest(res, 'customerId zorunludur.');
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
            select id,title,status,scheduled_date,is_active,created_at
            from public.work_orders
            where customer_id = $1
              ${activeSql}
            order by created_at desc
          `,
          values,
        );
        return ok(res, { items: result.rows });
      }

      case 'customers_for_transfer': {
        const result = await query(
          `select id,name,is_active from public.customers order by name asc`,
        );
        return ok(res, { items: result.rows });
      }

      case 'service_list': {
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = 'where true';
        if (!showPassive) {
          values.push(true);
          whereSql += ` and s.is_active = $${values.length}`;
        }
        const result = await query(
          `
            select
              s.id,
              s.title,
              s.status,
              s.created_at,
              s.customer_id,
              c.name as customer_name,
              s.total_amount,
              s.currency
            from public.service_records s
            left join public.customers c on c.id = s.customer_id
            ${whereSql}
            order by s.created_at desc
            limit 500
          `,
          values,
        );
        return ok(res, { items: result.rows });
      }

      case 'service_detail': {
        const id = String(req.query.serviceId || '').trim();
        if (!id) return badRequest(res, 'serviceId zorunludur.');
        const result = await query(
          `
            select
              s.id,
              s.title,
              s.status,
              s.created_at,
              s.notes,
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
            where s.id = $1
            limit 1
          `,
          [id],
        );
        return ok(res, result.rows[0] || null);
      }

      case 'definition_device_brands': {
        const result = await query(
          `select id,name,is_active,created_at from public.device_brands order by name asc`,
        );
        return ok(res, { items: result.rows });
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
        return ok(res, { items: result.rows });
      }

      case 'definition_work_order_types': {
        const result = await query(
          `select * from public.work_order_types where is_active = true order by sort_order asc`,
        );
        return ok(res, { items: result.rows });
      }

      case 'definition_tax_rates': {
        const result = await query(
          `select * from public.tax_rates where is_active = true order by sort_order asc`,
        );
        return ok(res, { items: result.rows });
      }

      case 'definition_cities': {
        const result = await query(
          `select id,name,code,is_active,created_at from public.cities where is_active = true order by name asc`,
        );
        return ok(res, { items: result.rows });
      }

      case 'definition_fiscal_symbols': {
        const result = await query(
          `select id,name,code,is_active,created_at from public.fiscal_symbols where is_active = true order by name asc`,
        );
        return ok(res, { items: result.rows });
      }

      case 'definition_business_activity_types': {
        const result = await query(
          `select id,name,is_active,created_at from public.business_activity_types where is_active = true order by name asc`,
        );
        return ok(res, { items: result.rows });
      }

      case 'application_form_print_settings': {
        const result = await query(
          `select * from public.application_form_settings where id = 'default' limit 1`,
        );
        return ok(res, result.rows[0] || null);
      }

      case 'scrap_form_print_settings': {
        const result = await query(
          `select * from public.scrap_form_settings where id = 'default' limit 1`,
        );
        return ok(res, result.rows[0] || null);
      }

      case 'transfer_form_print_settings': {
        const result = await query(
          `select * from public.transfer_form_settings where id = 'default' limit 1`,
        );
        return ok(res, result.rows[0] || null);
      }

      case 'form_application_customers': {
        const result = await query(
          `
            select
              id,
              name,
              vkn,
              tckn_ms,
              city,
              address,
              director_name,
              is_active
            from public.customers
            order by name asc
          `,
        );
        return ok(res, { items: result.rows });
      }

      case 'form_customers_bulk': {
        const idsRaw = String(req.query.ids || '').trim();
        if (!idsRaw) return ok(res, { items: [] });
        const ids = idsRaw
          .split(',')
          .map((id) => id.trim())
          .filter((id) => id.length > 0)
          .slice(0, 500);
        if (!ids.length) return ok(res, { items: [] });

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
        return ok(res, { items: result.rows });
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
        return ok(res, { items: result.rows });
      }

      case 'form_application_list': {
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
              is_active,
              created_at
            from public.application_forms
            ${whereSql}
            order by created_at desc
            limit 500
          `,
          values,
        );
        return ok(res, { items: result.rows });
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
        return ok(res, { items: result.rows });
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
        return ok(res, { items: result.rows });
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
        return ok(res, { items: result.rows });
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
        return ok(res, { items: result.rows });
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
        return ok(res, { items: result.rows });
      }

      case 'customers_lookup': {
        const result = await query(
          `select id,name,is_active from public.customers order by name asc`,
        );
        return ok(res, { items: result.rows });
      }

      case 'products_lines': {
        const search = String(req.query.search || '').trim();
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = 'where true';

        if (!(user.role === 'admin' && showPassive)) {
          values.push(true);
          whereSql += ` and l.is_active = $${values.length}`;
        }

        if (search) {
          values.push(`%${search}%`);
          whereSql += ` and (l.number ilike $${values.length} or l.sim_number ilike $${values.length})`;
        }

        const result = await query(
          `
            select
              l.id,
              l.label,
              l.number,
              l.sim_number,
              l.starts_at,
              l.ends_at,
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
            limit 500
          `,
          values,
        );
        return ok(res, { items: result.rows });
      }

      case 'products_licenses': {
        const search = String(req.query.search || '').trim();
        const showPassive = parseBoolean(req.query.showPassive, false);
        const values = [];
        let whereSql = `where true`;

        if (!(user.role === 'admin' && showPassive)) {
          values.push(true);
          whereSql += ` and lic.is_active = $${values.length}`;
        }

        if (search) {
          values.push(`%${search}%`);
          whereSql += ` and lic.name ilike $${values.length}`;
        }

        const result = await query(
          `
            select
              lic.id,
              lic.name,
              lic.license_type,
              lic.starts_at,
              lic.ends_at,
              lic.is_active,
              lic.customer_id,
              c.name as customer_name
            from public.licenses lic
            left join public.customers c on c.id = lic.customer_id
            ${whereSql}
            order by lic.ends_at asc nulls last, lic.created_at desc
            limit 500
          `,
          values,
        );
        return ok(res, { items: result.rows });
      }

      default:
        return badRequest(res, `Bilinmeyen resource: ${resource}`);
    }
  } catch (error) {
    return serverError(res, error);
  }
};
