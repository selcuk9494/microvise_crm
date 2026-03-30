const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const { ok, forbidden, unauthorized, methodNotAllowed, serverError } = require('./_lib/http');

module.exports = async (req, res) => {
  if (req.method !== 'GET') {
    return methodNotAllowed(res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    if (!hasPageAccess(user, 'is_emirleri')) {
      return forbidden(res, 'İş emirlerine erişim yetkiniz yok.');
    }

    const values = [];
    let assignedFilterSql = '';
    if (user.role !== 'admin') {
      values.push(user.id);
      assignedFilterSql = `and w.assigned_to = $${values.length}`;
    }

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
          wt.name as work_order_type_name,
          coalesce(
            json_agg(
              json_build_object(
                'amount', p.amount,
                'currency', p.currency,
                'description', p.description,
                'paid_at', p.paid_at,
                'payment_method', p.payment_method,
                'is_active', p.is_active
              )
              order by p.paid_at desc
            ) filter (where p.id is not null),
            '[]'::json
          ) as payments
        from public.work_orders w
        left join public.customers c on c.id = w.customer_id
        left join public.branches b on b.id = w.branch_id
        left join public.work_order_types wt on wt.id = w.work_order_type_id
        left join public.payments p on p.work_order_id = w.id and p.is_active = true
        where true
          ${assignedFilterSql}
        group by
          w.id,
          c.name,
          b.name,
          wt.name
        order by
          case w.status
            when 'open' then 0
            when 'in_progress' then 1
            when 'done' then 2
            else 99
          end,
          w.sort_order asc,
          w.created_at desc
      `,
      values,
    );

    return ok(res, { items: result.rows });
  } catch (error) {
    return serverError(res, error);
  }
};
