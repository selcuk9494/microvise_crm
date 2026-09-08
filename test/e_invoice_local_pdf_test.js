const { test } = require('node:test');
const assert = require('node:assert/strict');

const { clientAllowsLocalPdf } = require('../api/e-invoice').testUtils;

test('vercel host does not allow local open-pdf', () => {
  const prev = process.env.VERCEL;
  process.env.VERCEL = '1';
  try {
    assert.equal(
      clientAllowsLocalPdf({ headers: { host: 'crm.microvise.net' } }),
      false,
    );
  } finally {
    if (prev == null) delete process.env.VERCEL;
    else process.env.VERCEL = prev;
  }
});

test('localhost host allows local open-pdf', () => {
  const prevVercel = process.env.VERCEL;
  const prevOrigin = process.env.MICROVISE_LOCAL_ORIGIN;
  delete process.env.VERCEL;
  delete process.env.MICROVISE_LOCAL_ORIGIN;
  try {
    assert.equal(
      clientAllowsLocalPdf({ headers: { host: '127.0.0.1:4000' } }),
      true,
    );
    assert.equal(
      clientAllowsLocalPdf({ headers: { host: 'localhost:4000' } }),
      true,
    );
    assert.equal(
      clientAllowsLocalPdf({ headers: { host: 'crm.microvise.net' } }),
      false,
    );
  } finally {
    if (prevVercel == null) delete process.env.VERCEL;
    else process.env.VERCEL = prevVercel;
    if (prevOrigin == null) delete process.env.MICROVISE_LOCAL_ORIGIN;
    else process.env.MICROVISE_LOCAL_ORIGIN = prevOrigin;
  }
});
