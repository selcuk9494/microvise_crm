const { query } = require('./db');

function getSupabaseAuthConfig() {
  const url = process.env.SUPABASE_URL;
  const publishableKey =
    process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
  if (!url || !publishableKey) {
    throw new Error('SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required.');
  }
  return { url, publishableKey };
}

async function getAccessToken(req) {
  const header = req.headers.authorization || req.headers.Authorization;
  if (!header || typeof header !== 'string') return null;
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  return token || null;
}

async function getAuthenticatedUser(req) {
  const accessToken = await getAccessToken(req);
  if (!accessToken) {
    return null;
  }

  const { url, publishableKey } = getSupabaseAuthConfig();
  const response = await fetch(`${url}/auth/v1/user`, {
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    return null;
  }

  const authUser = await response.json();
  const profileResult = await query(
    `
      select
        id,
        email,
        full_name,
        role,
        coalesce(page_permissions, '{}'::text[]) as page_permissions,
        coalesce(action_permissions, '{}'::text[]) as action_permissions
      from public.users
      where id = $1
      limit 1
    `,
    [authUser.id],
  );

  const profile = profileResult.rows[0];
  if (!profile) {
    return {
      id: authUser.id,
      email: authUser.email || null,
      full_name:
        authUser.user_metadata?.full_name ||
        authUser.user_metadata?.name ||
        null,
      role: 'personel',
      page_permissions: [],
      action_permissions: [],
    };
  }

  return profile;
}

function hasPageAccess(user, pageKey) {
  if (!user) return false;
  if (user.role === 'admin') return true;
  return Array.isArray(user.page_permissions)
    ? user.page_permissions.includes(pageKey)
    : false;
}

module.exports = {
  getAuthenticatedUser,
  hasPageAccess,
};
