const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  ensureWorkOrdersPaymentRequiredColumn,
  ensureWorkOrdersStatusCheckConstraint,
} = require('./_lib/schema');
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

    await ensureWorkOrdersPaymentRequiredColumn();
    await ensureWorkOrdersStatusCheckConstraint();

    if (req.method === 'POST') {
      const body = await readJson(req);

      const customerId = String(body.customer_id || '').trim();
      if (!customerId) return badRequest(res, 'customer_id zorunludur.');

      const title = String(body.title || '').trim();
      if (!title) return badRequest(res, 'title zorunludur.');

      const assignedToRaw = String(body.assigned_to || '').trim();
      const assignedTo = user.role === 'admin' ? assignedToRaw : user.id;
      if (!assignedTo) return badRequest(res, 'assigned_to zorunludur.');

      if (typeof body.payment_required !== 'boolean') {
        return badRequest(res, 'payment_required zorunludur.');
      }

      const allowedStatuses = new Set([
        'open',
        'in_progress',
        'approval_pending',
        'done',
        'cancelled',
      ]);
      const requestedStatus =
        body.status == null ? null : String(body.status || '').trim() || null;
      const status =
        requestedStatus && allowedStatuses.has(requestedStatus)
          ? requestedStatus
          : 'open';
      const finalStatus =
        user.role === 'admin'
          ? status
          : status === 'approval_pending'
            ? 'approval_pending'
            : 'open';

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
        body.payment_required,
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
            payment_required,
            status,
            is_active,
            created_by
          )
          values (
            $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,
            '${finalStatus}',
            true,
            $13
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
      const paymentRequired =
        typeof body.payment_required === 'boolean' ? body.payment_required : null;

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
        assignedTo == null &&
        paymentRequired == null
      ) {
        return badRequest(res, 'Güncellenecek alan bulunamadı.');
      }

      const values = [
        status,
        sortOrder,
        isActive,
        paymentRequired,
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
            payment_required = coalesce($4, payment_required),
            title = coalesce($5, title),
            description = coalesce($6, description),
            address = coalesce($7, address),
            city = coalesce($8, city),
            branch_id = coalesce($9, branch_id),
            work_order_type_id = coalesce($10, work_order_type_id),
            contact_phone = coalesce($11, contact_phone),
            location_link = coalesce($12, location_link),
            scheduled_date = coalesce($13, scheduled_date),
            assigned_to = coalesce($14, assigned_to)
          where id = $15
            ${assignedSql}
        `,
        values,
      );

      return ok(res, { ok: true });
    }

    if (req.method !== 'GET') {
      return methodNotAllowed(res, 'GET, POST, PATCH');
    }

    const status = String(req.query.status || 'all').trim();
    const showPassiveRaw = String(req.query.showPassive || '').trim();
    const showPassive = showPassiveRaw === 'true' || showPassiveRaw === '1';
    const search = String(req.query.search || '').trim();
    const pageRaw = Number(req.query.page);
    const page = Number.isFinite(pageRaw) && pageRaw >= 1 ? pageRaw : 1;
    const pageSizeRaw = Number(req.query.pageSize);
    const pageSize =
      Number.isFinite(pageSizeRaw) && pageSizeRaw >= 1 && pageSizeRaw <= 1000
        ? pageSizeRaw
        : 500;
    const offset = (page - 1) * pageSize;

    const values = [];
    const conditions = ['true'];

    if (!showPassive) {
      conditions.push('w.is_active = true');
    }
    if (status && status !== 'all') {
      values.push(status);
      conditions.push(`w.status = $${values.length}`);
    }
    if (search) {
      values.push(`%${search}%`);
      const p = `$${values.length}`;
      conditions.push(
        `(w.title ilike ${p} or c.name ilike ${p} or b.name ilike ${p} or w.id::text ilike ${p})`,
      );
    }
    if (user.role !== 'admin') {
      values.push(user.id);
      const p = `$${values.length}`;
      conditions.push(`(w.assigned_to = ${p} or w.created_by = ${p})`);
    }

    values.push(pageSize);
    values.push(offset);
    const limitParam = `$${values.length - 1}`;
    const offsetParam = `$${values.length}`;
    const whereSql = `where ${conditions.join(' and ')}`;

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
          '[]'::json as payments
        from public.work_orders w
        left join public.customers c on c.id = w.customer_id
        left join public.branches b on b.id = w.branch_id
        left join public.users u on u.id = w.assigned_to
        left join public.work_order_types wt on wt.id = w.work_order_type_id
        ${whereSql}
        order by
          case w.status
            when 'open' then 0
            when 'in_progress' then 1
            when 'approval_pending' then 2
            when 'done' then 3
            else 99
          end,
          w.sort_order asc,
          w.created_at desc
        limit ${limitParam}
        offset ${offsetParam}
      `,
      values,
    );

    return ok(res, { items: result.rows });
  } catch (error) {
    return serverError(res, error);
  }
};
