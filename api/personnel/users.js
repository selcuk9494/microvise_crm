const crypto = require('crypto');

const { getAuthenticatedUser, hasPageAccess } = require('../_lib/auth');
const { query } = require('../_lib/db');
const { ensureUsersAuthColumns } = require('../_lib/schema');
const {
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('../_lib/http');

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
  let value = String(email || '').trim().toLowerCase();
  while (value.endsWith('.')) {
    value = value.slice(0, -1).trimEnd();
  }
  return value;
}

function normalizeTextArray(value) {
  if (!Array.isArray(value)) return null;
  return value
    .map((v) => String(v || '').trim())
    .filter((v) => v.length > 0)
    .slice(0, 200);
}

function uuidV4() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const b = crypto.randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = b.toString('hex');
  return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}`;
}

async function tryAdminCreatePersonnel({
  email,
  password,
  fullName,
  role,
  pagePermissions,
  actionPermissions,
}) {
  if (!password || String(password).length < 6) return null;
  try {
    const result = await query(
      `select public.admin_create_personnel($1,$2,$3,$4,$5::text[],$6::text[]) as id`,
      [
        email,
        String(password),
        fullName,
        role,
        pagePermissions,
        actionPermissions,
      ],
    );
    return result.rows[0]?.id || null;
  } catch (_) {
    return null;
  }
}

async function setPasswordHash({ id, password }) {
  if (!password || String(password).length < 6) return false;
  await ensureUsersAuthColumns();
  await query(
    `
      update public.users
      set password_hash = crypt($2, gen_salt('bf'))
      where id = $1
    `,
    [id, String(password)],
  );
  return true;
}

module.exports = async (req, res) => {
  if (!['POST', 'PATCH'].includes(req.method)) {
    return methodNotAllowed(res, 'POST, PATCH');
  }

  try {
    await ensureUsersAuthColumns();
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    if (!hasPageAccess(user, 'personel')) {
      return forbidden(res, 'Personel yönetimine erişim yetkiniz yok.');
    }
    if (user.role !== 'admin') {
      return forbidden(res, 'Bu işlem için admin yetkisi gerekir.');
    }

    const body = await readJson(req);
    const op = String(body.op || '').trim();

    if (op === 'delete') {
      const id = String(body.id || '').trim();
      if (!id) return badRequest(res, 'id zorunludur.');
      await query(`delete from public.users where id = $1`, [id]);
      return ok(res, { ok: true });
    }

    if (op === 'set_password') {
      const id = String(body.id || '').trim();
      const password = String(body.password || '');
      if (!id) return badRequest(res, 'id zorunludur.');
      if (!password || password.length < 6) {
        return badRequest(res, 'Şifre en az 6 karakter olmalıdır.');
      }
      try {
        await query(`select public.admin_update_personnel_password($1,$2)`, [
          id,
          password,
        ]);
      } catch (_) {
        await setPasswordHash({ id, password });
      }
      return ok(res, { ok: true });
    }

    const email = normalizeEmail(body.email);
    const fullName = String(body.full_name || '').trim();
    const role = String(body.role || 'personel').trim() || 'personel';
    const pagePermissions = normalizeTextArray(body.page_permissions);
    const actionPermissions = normalizeTextArray(body.action_permissions);

    if (!email || !email.includes('@')) {
      return badRequest(res, 'Geçerli bir e-posta gerekli.');
    }
    if (!fullName || fullName.length < 2) {
      return badRequest(res, 'Ad soyad gerekli.');
    }
    if (!['admin', 'personel'].includes(role)) {
      return badRequest(res, 'Geçersiz rol.');
    }

    const existing = await query(
      `select id from public.users where lower(email) = $1 limit 1`,
      [email],
    );
    const existingId = existing.rows[0]?.id || null;

    if (req.method === 'POST') {
      if (existingId) {
        await query(
          `
            update public.users
            set
              full_name = $1,
              role = $2,
              page_permissions = coalesce($3::text[], page_permissions),
              action_permissions = coalesce($4::text[], action_permissions)
            where id = $5
          `,
          [fullName, role, pagePermissions, actionPermissions, existingId],
        );
        const password = String(body.password || '');
        if (password && password.length >= 6) {
          await setPasswordHash({ id: existingId, password });
        }
        return ok(res, { ok: true, id: existingId, updated: true });
      }

      const password = String(body.password || '');
      const rpcId = await tryAdminCreatePersonnel({
        email,
        password,
        fullName,
        role,
        pagePermissions,
        actionPermissions,
      });
      if (rpcId) {
        try {
          await setPasswordHash({ id: rpcId, password });
        } catch (_) {}
        return ok(res, { ok: true, id: rpcId, created: true });
      }

      const id = uuidV4();
      await query(
        `
          insert into public.users (
            id,
            email,
            full_name,
            role,
            page_permissions,
            action_permissions,
            is_active
          )
          values ($1,$2,$3,$4,coalesce($5::text[], '{}'::text[]),coalesce($6::text[], '{}'::text[]),true)
        `,
        [
          id,
          email,
          fullName,
          role,
          pagePermissions,
          actionPermissions,
        ],
      );
      if (password && password.length >= 6) {
        await setPasswordHash({ id, password });
      }
      return ok(res, { ok: true, id, created: true });
    }

    const id = String(body.id || existingId || '').trim();
    if (!id) return badRequest(res, 'id zorunludur.');

    await query(
      `
        update public.users
        set
          email = $1,
          full_name = $2,
          role = $3,
          page_permissions = coalesce($4::text[], page_permissions),
          action_permissions = coalesce($5::text[], action_permissions)
        where id = $6
      `,
      [email, fullName, role, pagePermissions, actionPermissions, id],
    );
    return ok(res, { ok: true, id });
  } catch (error) {
    return serverError(res, error);
  }
};
