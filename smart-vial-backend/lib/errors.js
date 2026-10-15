class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function sendError(res, error) {
  // Never return DB errors, tokens, bodies, connection strings or user identifiers.
  if (error instanceof ApiError) return res.status(error.status).json({ error: error.message, code: error.code });
  return res.status(503).json({ error: 'Service temporarily unavailable. Please retry.', code: 'service_unavailable' });
}

function handler(fn) {
  return async (req, res) => {
    try { return await fn(req, res); } catch (error) { return sendError(res, error); }
  };
}

module.exports = { ApiError, sendError, handler };
