const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (!chunks.length) return {};
  const text = Buffer.concat(chunks).toString('utf8').trim();
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (_) {
    return {};
  }
}

module.exports = async (req, res) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    if (!hasPageAccess(user, 'is_emirleri')) {
      return forbidden(res, 'İş emirlerine erişim yetkiniz yok.');
    }

    if (req.method === 'PATCH') {
      const body = await readJson(req);
      const id = String(body.id || '').trim();
      if (!id) return badRequest(res, 'id zorunludur.');

      const status =
        body.status == null ? null : String(body.status || '').trim() || null;
      const sortOrder =
        body.sort_order == null
          ? null
          : Number.isFinite(Number(body.sort_order))
            ? Number(body.sort_order)
            : null;
      const isActive =
        typeof body.is_active === 'boolean' ? body.is_active : null;

      if (status == null && sortOrder == null && isActive == null) {
        return badRequest(res, 'Güncellenecek alan bulunamadı.');
      }

      const values = [status, sortOrder, isActive, id];
      let assignedSql = '';
      if (user.role !== 'admin') {
        values.push(user.id);
        assignedSql = `and assigned_to = $${values.length}`;
      }

      await query(
        `
          update public.work_orders
          set
            status = coalesce($1, status),
            sort_order = coalesce($2, sort_order),
            is_active = coalesce($3, is_active)
          where id = $4
            ${assignedSql}
        `,
        values,
      );

      return ok(res, { ok: true });
    }

    if (req.method !== 'GET') {
      return methodNotAllowed(res, 'GET, PATCH');
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
