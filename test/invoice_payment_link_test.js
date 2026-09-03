const { test } = require('node:test');
const assert = require('node:assert/strict');

const { chargeAmountForLink } = require('../api/_lib/invoice_payment');

test('chargeAmountForLink takes the smaller of link amount and remaining', () => {
  assert.equal(chargeAmountForLink(420.02, 420.02), 420.02);
  assert.equal(chargeAmountForLink(420.02, 200), 200);
  assert.equal(chargeAmountForLink(100, 250.55), 100);
  assert.equal(chargeAmountForLink(100.555, 100.554), 100.55);
});

test('chargeAmountForLink does not charge when remaining or link is zero', () => {
  assert.equal(chargeAmountForLink(420.02, 0), 0);
  assert.equal(chargeAmountForLink(420.02, 0.004), 0);
  assert.equal(chargeAmountForLink(0, 50), 0);
  assert.equal(chargeAmountForLink(null, 50), 0);
});
