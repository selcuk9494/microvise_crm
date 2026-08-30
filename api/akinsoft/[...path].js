const { handleAkinsoftRequest } = require('../../scripts/local_server');
require('../../scripts/akinsoft_finance_sync');

module.exports = async function handler(req, res) {
  return handleAkinsoftRequest(req, res);
};
