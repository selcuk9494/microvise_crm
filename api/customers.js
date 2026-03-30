const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  ok,
  forbidden,
  unauthorized,
  methodNotAllowed,
  parseBoolean,
  parseInteger,
  serverError,
} = require('./_lib/http');

function resolveSort(sort) {
  switch (sort) {
    case 'nameAsc':
      return 'c.name asc';
    case 'nameDesc':
      return 'c.name desc';
    case 'id':
    default:
      return 'c.created_at asc';
  }
}

module.exports = async (req, res) => {
  if (req.method !== 'GET') {
    return methodNotAllowed(res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    if (!hasPageAccess(user, 'musteriler')) {
      return forbidden(res, 'Müşteri listesine erişim yetkiniz yok.');
    }

    const search = String(req.query.search || '').trim();
    const city = String(req.query.city || '').trim();
    const showPassive = parseBoolean(req.query.showPassive, false);
    const page = parseInteger(req.query.page, 1, { min: 1 });
    const pageSize = parseInteger(req.query.pageSize, 50, { min: 1, max: 100 });
    const offset = (page - 1) * pageSize;
    const sortSql = resolveSort(String(req.query.sort || 'id'));

    const conditions = [];
    const values = [];

    if (!showPassive) {
      values.push(true);
      conditions.push(`c.is_active = $${values.length}`);
    }

    if (city) {
      values.push(city);
      conditions.push(`c.city = $${values.length}`);
    }

    if (search) {
      values.push(`%${search}%`);
      conditions.push(`c.name ilike $${values.length}`);
    }

    const whereSql = conditions.length
      ? `where ${conditions.join(' and ')}`
      : '';

    const countResult = await query(
      `select count(*)::int as total_count from public.customers c ${whereSql}`,
      values,
    );
    const totalCount = countResult.rows[0]?.total_count ?? 0;

    const dataValues = [...values, pageSize, offset];
    const rowsResult = await query(
      `
        select
          c.id,
          c.name,
          c.city,
          c.address,
          c.director_name,
          c.email,
          c.phone_1,
          c.phone_1_title,
          c.phone_2,
          c.phone_2_title,
          c.phone_3,
          c.phone_3_title,
          c.vkn,
          c.tckn_ms,
          c.notes,
          c.is_active,
          c.created_at,
          coalesce(lines.active_line_count, 0)::int as active_line_count,
          coalesce(licenses.active_gmp3_count, 0)::int as active_gmp3_count
        from public.customers c
        left join lateral (
          select count(*) as active_line_count
          from public.lines l
          where l.customer_id = c.id and l.is_active = true
        ) lines on true
        left join lateral (
          select count(*) as active_gmp3_count
          from public.licenses lic
          where lic.customer_id = c.id
            and lic.is_active = true
            and lic.license_type = 'gmp3'
        ) licenses on true
        ${whereSql}
        order by ${sortSql}
        limit $${dataValues.length - 1} offset $${dataValues.length}
      `,
      dataValues,
    );

    return ok(res, {
      page,
      pageSize,
      totalCount,
      hasNextPage: offset + rowsResult.rows.length < totalCount,
      items: rowsResult.rows,
    });
  } catch (error) {
    return serverError(res, error);
  }
};
