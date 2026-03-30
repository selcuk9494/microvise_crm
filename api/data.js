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
    if (
      resource === 'application_form_print_settings' ||
      resource === 'scrap_form_print_settings' ||
      resource === 'transfer_form_print_settings'
    ) {
      if (!requirePage(user, 'formlar', res)) return;
    }

    switch (resource) {
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

      default:
        return badRequest(res, `Bilinmeyen resource: ${resource}`);
    }
  } catch (error) {
    return serverError(res, error);
  }
};
