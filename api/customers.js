const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  parseBoolean,
  parseInteger,
  serverError,
} = require('./_lib/http');

const columnsCache = new Map();

async function getColumns(table) {
  if (columnsCache.has(table)) return columnsCache.get(table);
  const result = await query(
    `
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = $1
      order by ordinal_position asc
    `,
    [table],
  );
  const columns = result.rows
    .map((r) => r.column_name)
    .filter((c) => typeof c === 'string' && c.length > 0);
  columnsCache.set(table, columns);
  return columns;
}

async function tableExists(table) {
  try {
    const result = await query(
      `
        select 1
        from information_schema.tables
        where table_schema = 'public'
          and table_name = $1
        limit 1
      `,
      [table],
    );
    return result.rows.length > 0;
  } catch (_) {
    return false;
  }
}

function quoteIdent(name) {
  return `"${String(name).replace(/"/g, '""')}"`;
}

function pickValues(values, allowedColumns) {
  if (!values || typeof values !== 'object') return {};
  const out = {};
  for (const key of Object.keys(values)) {
    if (!allowedColumns.includes(key)) continue;
    const value = values[key];
    if (value === undefined) continue;
    out[key] = value;
  }
  return out;
}

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

function normalizeEmail(email) {
  const value = String(email || '').trim();
  return value ? value.toLowerCase() : null;
}

function normalizeDigits(value) {
  const digits = String(value || '').replace(/[^0-9]/g, '');
  return digits ? digits : null;
}

async function replaceCustomerLocations({ customerId, locations, userId }) {
  const exists = await tableExists('customer_locations');
  if (!exists) return;

  await query(`delete from public.customer_locations where customer_id = $1`, [customerId]);
  if (!Array.isArray(locations) || locations.length === 0) return;

  for (const row of locations) {
    if (!row || typeof row !== 'object') continue;
    const title = row.title ? String(row.title).trim() : null;
    const description = row.description ? String(row.description).trim() : null;
    const address = row.address ? String(row.address).trim() : null;
    const locationLink = row.location_link
      ? String(row.location_link).trim()
      : null;
    const lat =
      row.location_lat == null ? null : Number.parseFloat(row.location_lat);
    const lng =
      row.location_lng == null ? null : Number.parseFloat(row.location_lng);

    if (
      !title &&
      !description &&
      !address &&
      !locationLink &&
      !(Number.isFinite(lat) && Number.isFinite(lng))
    ) {
      continue;
    }

    await query(
      `
        insert into public.customer_locations (
          customer_id,
          title,
          description,
          address,
          location_link,
          location_lat,
          location_lng,
          is_active,
          created_by
        )
        values ($1,$2,$3,$4,$5,$6,$7,true,$8)
      `,
      [
        customerId,
        title || address || description || 'Konum',
        description,
        address,
        locationLink,
        Number.isFinite(lat) ? lat : null,
        Number.isFinite(lng) ? lng : null,
        userId,
      ],
    );
  }
}

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
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    if (!hasPageAccess(user, 'musteriler')) {
      return forbidden(res, 'Müşteri listesine erişim yetkiniz yok.');
    }

    if (req.method === 'POST') {
      const body = await readJson(req);
      const name = String(body.name || '').trim();
      if (!name) return badRequest(res, 'name zorunludur.');

      const payloadRaw = {
        name,
        city: body.city ? String(body.city).trim() : null,
        address: body.address ? String(body.address).trim() : null,
        director_name: body.director_name ? String(body.director_name).trim() : null,
        email: normalizeEmail(body.email),
        vkn: normalizeDigits(body.vkn),
        tckn_ms: normalizeDigits(body.tckn_ms),
        phone_1_title: body.phone_1_title ? String(body.phone_1_title).trim() : null,
        phone_1: body.phone_1 ? String(body.phone_1).trim() : null,
        phone_2_title: body.phone_2_title ? String(body.phone_2_title).trim() : null,
        phone_2: body.phone_2 ? String(body.phone_2).trim() : null,
        phone_3_title: body.phone_3_title ? String(body.phone_3_title).trim() : null,
        phone_3: body.phone_3 ? String(body.phone_3).trim() : null,
        notes: body.notes ? String(body.notes).trim() : null,
        is_active: typeof body.is_active === 'boolean' ? body.is_active : true,
      };

      const customerColumns = await getColumns('customers');
      const payload = pickValues(payloadRaw, customerColumns);
      if (customerColumns.includes('created_by')) {
        payload.created_by = user.id;
      }
      if (customerColumns.includes('created_at') && payload.created_at == null) {
        payload.created_at = new Date().toISOString();
      }

      const keys = Object.keys(payload);
      if (!keys.length) return badRequest(res, 'Kayıt verisi bulunamadı.');

      const colSql = keys.map(quoteIdent).join(', ');
      const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
      const values = keys.map((k) => payload[k]);
      const result = await query(
        `
          insert into public.customers (${colSql})
          values (${placeholders})
          returning id
        `,
        values,
      );
      const id = result.rows[0]?.id;
      if (!id) return serverError(res, new Error('Customer insert failed.'));

      await replaceCustomerLocations({
        customerId: id,
        locations: body.locations,
        userId: user.id,
      });

      return ok(res, { ok: true, id });
    }

    if (req.method === 'PATCH') {
      const body = await readJson(req);
      const id = String(body.id || '').trim();
      if (!id) return badRequest(res, 'id zorunludur.');

      const payloadRaw = {
        name: body.name == null ? undefined : String(body.name || '').trim() || null,
        city: body.city == null ? undefined : String(body.city || '').trim() || null,
        address: body.address == null ? undefined : String(body.address || '').trim() || null,
        director_name:
          body.director_name == null
            ? undefined
            : String(body.director_name || '').trim() || null,
        email: body.email == null ? undefined : normalizeEmail(body.email),
        vkn: body.vkn == null ? undefined : normalizeDigits(body.vkn),
        tckn_ms: body.tckn_ms == null ? undefined : normalizeDigits(body.tckn_ms),
        phone_1_title:
          body.phone_1_title == null
            ? undefined
            : String(body.phone_1_title || '').trim() || null,
        phone_1: body.phone_1 == null ? undefined : String(body.phone_1 || '').trim() || null,
        phone_2_title:
          body.phone_2_title == null
            ? undefined
            : String(body.phone_2_title || '').trim() || null,
        phone_2: body.phone_2 == null ? undefined : String(body.phone_2 || '').trim() || null,
        phone_3_title:
          body.phone_3_title == null
            ? undefined
            : String(body.phone_3_title || '').trim() || null,
        phone_3: body.phone_3 == null ? undefined : String(body.phone_3 || '').trim() || null,
        notes: body.notes == null ? undefined : String(body.notes || '').trim() || null,
        is_active: typeof body.is_active === 'boolean' ? body.is_active : undefined,
      };

      const customerColumns = await getColumns('customers');
      const payload = pickValues(payloadRaw, customerColumns);
      const keys = Object.keys(payload);
      if (keys.length === 0 && !Array.isArray(body.locations)) {
        return badRequest(res, 'Güncellenecek alan bulunamadı.');
      }

      const setParts = [];
      const params = [];
      for (const key of keys) {
        params.push(payload[key]);
        setParts.push(`${quoteIdent(key)} = $${params.length}`);
      }
      params.push(id);

      if (setParts.length > 0) {
        await query(
          `
            update public.customers
            set ${setParts.join(', ')}
            where id = $${params.length}
          `,
          params,
        );
      }

      if (Array.isArray(body.locations)) {
        await replaceCustomerLocations({
          customerId: id,
          locations: body.locations,
          userId: user.id,
        });
      }

      return ok(res, { ok: true });
    }

    if (req.method !== 'GET') {
      return methodNotAllowed(res, 'GET, POST, PATCH');
    }

    const search = String(req.query.search || '').trim();
    const city = String(req.query.city || '').trim();
    const showPassive = parseBoolean(req.query.showPassive, false);
    const exportAll = parseBoolean(req.query.export, false);
    const page = parseInteger(req.query.page, 1, { min: 1 });
    const pageSize = parseInteger(req.query.pageSize, 50, { min: 1, max: 100 });
    const offset = (page - 1) * pageSize;
    const sortSql = resolveSort(String(req.query.sort || 'id'));

    const conditions = [];
    const values = [];

    if (!showPassive) {
      conditions.push(`coalesce(c.is_active, true) = true`);
    }

    if (city) {
      values.push(city);
      conditions.push(`c.city = $${values.length}`);
    }

    if (search) {
      values.push(`%${search}%`);
      conditions.push(
        `(c.name ilike $${values.length}
          or c.vkn ilike $${values.length}
          or c.tckn_ms ilike $${values.length}
          or c.phone_1 ilike $${values.length}
          or c.phone_2 ilike $${values.length}
          or c.phone_3 ilike $${values.length}
          or c.email ilike $${values.length})`,
      );
    }

    const whereSql = conditions.length
      ? `where ${conditions.join(' and ')}`
      : '';

    if (exportAll) {
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
            c.created_at
          from public.customers c
          ${whereSql}
          order by ${sortSql}
          limit 50000
        `,
        values,
      );

      return ok(res, {
        items: rowsResult.rows,
      });
    }

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
