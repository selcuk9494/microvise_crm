const { test } = require('node:test');
const assert = require('node:assert/strict');

const { normalizeCustomerSentVia } = require('../api/_lib/invoice_mail');

test('normalizeCustomerSentVia maps known channels', () => {
  assert.equal(normalizeCustomerSentVia('email'), 'email');
  assert.equal(normalizeCustomerSentVia('Mail'), 'email');
  assert.equal(normalizeCustomerSentVia('whatsapp'), 'whatsapp');
  assert.equal(normalizeCustomerSentVia('WA'), 'whatsapp');
  assert.equal(normalizeCustomerSentVia('manual'), 'manual');
  assert.equal(normalizeCustomerSentVia(''), 'manual');
  assert.equal(normalizeCustomerSentVia(null), 'manual');
});
