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
  await query(`delete from public.customer_locations where customer_id = $1`, [
    customerId,
  ]);
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

      const payload = {
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

      const result = await query(
        `
          insert into public.customers (
            name,
            city,
            address,
            director_name,
            email,
            vkn,
            tckn_ms,
            phone_1_title,
            phone_1,
            phone_2_title,
            phone_2,
            phone_3_title,
            phone_3,
            notes,
            is_active,
            created_by
          )
          values (
            $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16
          )
          returning id
        `,
        [
          payload.name,
          payload.city,
          payload.address,
          payload.director_name,
          payload.email,
          payload.vkn,
          payload.tckn_ms,
          payload.phone_1_title,
          payload.phone_1,
          payload.phone_2_title,
          payload.phone_2,
          payload.phone_3_title,
          payload.phone_3,
          payload.notes,
          payload.is_active,
          user.id,
        ],
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

      const name = body.name == null ? null : String(body.name || '').trim() || null;
      const city = body.city == null ? null : String(body.city || '').trim() || null;
      const address = body.address == null ? null : String(body.address || '').trim() || null;
      const directorName =
        body.director_name == null ? null : String(body.director_name || '').trim() || null;
      const email = body.email == null ? null : normalizeEmail(body.email);
      const vkn = body.vkn == null ? null : normalizeDigits(body.vkn);
      const tcknMs = body.tckn_ms == null ? null : normalizeDigits(body.tckn_ms);
      const phone1Title =
        body.phone_1_title == null ? null : String(body.phone_1_title || '').trim() || null;
      const phone1 = body.phone_1 == null ? null : String(body.phone_1 || '').trim() || null;
      const phone2Title =
        body.phone_2_title == null ? null : String(body.phone_2_title || '').trim() || null;
      const phone2 = body.phone_2 == null ? null : String(body.phone_2 || '').trim() || null;
      const phone3Title =
        body.phone_3_title == null ? null : String(body.phone_3_title || '').trim() || null;
      const phone3 = body.phone_3 == null ? null : String(body.phone_3 || '').trim() || null;
      const notes = body.notes == null ? null : String(body.notes || '').trim() || null;
      const isActive = typeof body.is_active === 'boolean' ? body.is_active : null;

      await query(
        `
          update public.customers
          set
            name = coalesce($1, name),
            city = coalesce($2, city),
            address = coalesce($3, address),
            director_name = coalesce($4, director_name),
            email = coalesce($5, email),
            vkn = coalesce($6, vkn),
            tckn_ms = coalesce($7, tckn_ms),
            phone_1_title = coalesce($8, phone_1_title),
            phone_1 = coalesce($9, phone_1),
            phone_2_title = coalesce($10, phone_2_title),
            phone_2 = coalesce($11, phone_2),
            phone_3_title = coalesce($12, phone_3_title),
            phone_3 = coalesce($13, phone_3),
            notes = coalesce($14, notes),
            is_active = coalesce($15, is_active)
          where id = $16
        `,
        [
          name,
          city,
          address,
          directorName,
          email,
          vkn,
          tcknMs,
          phone1Title,
          phone1,
          phone2Title,
          phone2,
          phone3Title,
          phone3,
          notes,
          isActive,
          id,
        ],
      );

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
