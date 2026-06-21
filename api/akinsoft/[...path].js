const { handleAkinsoftRequest } = require('../../scripts/local_server');

module.exports = async function handler(req, res) {
  return handleAkinsoftRequest(req, res);
};
