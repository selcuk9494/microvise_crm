const assert = require('node:assert/strict');
const test = require('node:test');

const { appleAudiences } = require('../api/_lib/apple_identity');

test('apple audiences always include the iOS bundle id', () => {
  const previous = {
    APPLE_BUNDLE_ID: process.env.APPLE_BUNDLE_ID,
    APPLE_SERVICE_ID: process.env.APPLE_SERVICE_ID,
    APPLE_CLIENT_IDS: process.env.APPLE_CLIENT_IDS,
  };
  delete process.env.APPLE_BUNDLE_ID;
  delete process.env.APPLE_SERVICE_ID;
  delete process.env.APPLE_CLIENT_IDS;
  try {
    assert.deepEqual(appleAudiences(), ['com.microvise.microviseCrm']);
    process.env.APPLE_SERVICE_ID = 'com.microvise.microviseCrm.web';
    process.env.APPLE_CLIENT_IDS = 'com.example.extra, com.microvise.microviseCrm';
    assert.deepEqual(appleAudiences(), [
      'com.microvise.microviseCrm',
      'com.microvise.microviseCrm.web',
      'com.example.extra',
    ]);
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
});
