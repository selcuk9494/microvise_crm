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

    if (req.method === 'POST') {
      const body = await readJson(req);

      const customerId = String(body.customer_id || '').trim();
      if (!customerId) return badRequest(res, 'customer_id zorunludur.');

      const title = String(body.title || '').trim();
      if (!title) return badRequest(res, 'title zorunludur.');

      const assignedToRaw = String(body.assigned_to || '').trim();
      const assignedTo = user.role === 'admin' ? assignedToRaw : user.id;
      if (!assignedTo) return badRequest(res, 'assigned_to zorunludur.');

      const scheduledDate =
        body.scheduled_date == null
          ? null
          : String(body.scheduled_date || '').trim() || null;

      const values = [
        customerId,
        body.branch_id ? String(body.branch_id).trim() : null,
        body.work_order_type_id ? String(body.work_order_type_id).trim() : null,
        title,
        body.description ? String(body.description).trim() : null,
        body.address ? String(body.address).trim() : null,
        body.city ? String(body.city).trim() : null,
        assignedTo,
        scheduledDate,
        body.contact_phone ? String(body.contact_phone).trim() : null,
        body.location_link ? String(body.location_link).trim() : null,
        user.id,
      ];

      const result = await query(
        `
          insert into public.work_orders (
            customer_id,
            branch_id,
            work_order_type_id,
            title,
            description,
            address,
            city,
            assigned_to,
            scheduled_date,
            contact_phone,
            location_link,
            status,
            is_active,
            created_by
          )
          values (
            $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,
            'open',
            true,
            $12
          )
          returning id
        `,
        values,
      );

      return ok(res, { ok: true, id: result.rows[0]?.id || null });
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

      const title =
        body.title == null ? null : String(body.title || '').trim() || null;
      const description =
        body.description == null
          ? null
          : String(body.description || '').trim() || null;
      const address =
        body.address == null ? null : String(body.address || '').trim() || null;
      const city =
        body.city == null ? null : String(body.city || '').trim() || null;
      const branchId =
        body.branch_id == null
          ? null
          : String(body.branch_id || '').trim() || null;
      const workOrderTypeId =
        body.work_order_type_id == null
          ? null
          : String(body.work_order_type_id || '').trim() || null;
      const contactPhone =
        body.contact_phone == null
          ? null
          : String(body.contact_phone || '').trim() || null;
      const locationLink =
        body.location_link == null
          ? null
          : String(body.location_link || '').trim() || null;
      const scheduledDate =
        body.scheduled_date == null
          ? null
          : String(body.scheduled_date || '').trim() || null;
      const assignedTo =
        body.assigned_to == null
          ? null
          : String(body.assigned_to || '').trim() || null;

      if (
        status == null &&
        sortOrder == null &&
        isActive == null &&
        title == null &&
        description == null &&
        address == null &&
        city == null &&
        branchId == null &&
        workOrderTypeId == null &&
        contactPhone == null &&
        locationLink == null &&
        scheduledDate == null &&
        assignedTo == null
      ) {
        return badRequest(res, 'Güncellenecek alan bulunamadı.');
      }

      const values = [
        status,
        sortOrder,
        isActive,
        title,
        description,
        address,
        city,
        branchId,
        workOrderTypeId,
        contactPhone,
        locationLink,
        scheduledDate,
        user.role === 'admin' ? assignedTo : null,
        id,
      ];
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
            is_active = coalesce($3, is_active),
            title = coalesce($4, title),
            description = coalesce($5, description),
            address = coalesce($6, address),
            city = coalesce($7, city),
            branch_id = coalesce($8, branch_id),
            work_order_type_id = coalesce($9, work_order_type_id),
            contact_phone = coalesce($10, contact_phone),
            location_link = coalesce($11, location_link),
            scheduled_date = coalesce($12, scheduled_date),
            assigned_to = coalesce($13, assigned_to)
          where id = $14
            ${assignedSql}
        `,
        values,
      );

      return ok(res, { ok: true });
    }

    if (req.method !== 'GET') {
      return methodNotAllowed(res, 'GET, POST, PATCH');
    }

    const values = [];
    let assignedFilterSql = '';
    if (user.role !== 'admin') {
      values.push(user.id);
      assignedFilterSql = `and (w.assigned_to = $${values.length} or w.created_by = $${values.length})`;
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
