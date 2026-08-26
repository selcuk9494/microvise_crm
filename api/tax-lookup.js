'use strict';

const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const {
  handleCors,
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');
const { lookupTaxpayer } = require('./_lib/tax-lookup');

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,OPTIONS')) return;
  if (req.method !== 'GET') {
    return methodNotAllowed(req, res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);
    if (
      !hasPageAccess(user, 'musteriler') &&
      !hasPageAccess(user, 'e_fatura') &&
      !hasPageAccess(user, 'formlar')
    ) {
      return forbidden(req, res, 'Mükellef sorgusu için yetkiniz yok.');
    }

    const q = String(req.query?.q || '').trim();
    if (!q) {
      return badRequest(
        req,
        res,
        'Kimlik no, VKN veya mükellef numarası (MŞ…) girin.',
      );
    }

    const result = await lookupTaxpayer(q);
    return ok(req, res, result);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Mükellef sorgusu başarısız.';
    if (
      /bulunamadı|geçerli|birden fazla|girin|captcha|oturum/i.test(message)
    ) {
      return badRequest(req, res, message);
    }
    return serverError(req, res, error);
  }
};
