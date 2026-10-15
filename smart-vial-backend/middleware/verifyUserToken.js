const { Pool } = require('pg');
const config = require('../config/config');

// Same opaque mobile session token and exact Prisma table mapping as the main API.
// No cookie cache, alternate JWT, role supplied by a caller or separate auth issuer.
// Prisma's DateTime columns are UTC timestamp-without-timezone. Return a
// timestamptz so node-postgres cannot reinterpret them in the server's local TZ.
const SESSION_QUERY = 'SELECT s.id AS session_id, s."userId" AS user_id, (s."expiresAt" AT TIME ZONE \'UTC\') AS expires_at FROM "Session" s JOIN "User" u ON u.id = s."userId" WHERE s.token = $1 AND s."expiresAt" > (NOW() AT TIME ZONE \'UTC\') LIMIT 1';
const USER_EXISTS_QUERY = 'SELECT id FROM "User" WHERE id = $1 LIMIT 1';
let pool;
function sessionPool() {
  if (!config.databaseUrl) throw new Error('Session database is not configured');
  pool ||= new Pool({ connectionString: config.databaseUrl, max: 5, connectionTimeoutMillis: 5000, statement_timeout: 5000 });
  return pool;
}
function querySession(token) {
  return sessionPool().query(SESSION_QUERY, [token]);
}

function createVerifyToken({ query = querySession, now = () => new Date() } = {}) {
  return async (req, res, next) => {
    const header = req.headers.authorization;
    const match = typeof header === 'string' && /^Bearer ([A-Za-z0-9._~+\/-]{16,512}=*)$/i.exec(header);
    if (!match) return res.status(401).json({ error: 'A valid session is required', code: 'unauthorized' });
    try {
      const result = await query(match[1]);
      const session = result.rows[0];
      if (!session || typeof session.user_id !== 'string' || !Number.isFinite(+new Date(session.expires_at)) || +new Date(session.expires_at) <= +now()) {
        return res.status(401).json({ error: 'A valid session is required', code: 'unauthorized' });
      }
      req.user_id = session.user_id;
      req.user_role = 'user';
      req.user = { id: session.user_id };
      req.session = { id: session.session_id, expiresAt: session.expires_at };
      return next();
    } catch {
      return res.status(503).json({ error: 'Session verification temporarily unavailable', code: 'service_unavailable' });
    }
  };
}

module.exports = createVerifyToken();
module.exports.createVerifyToken = createVerifyToken;
module.exports.SESSION_QUERY = SESSION_QUERY;
module.exports.USER_EXISTS_QUERY = USER_EXISTS_QUERY;
module.exports.canonicalUserExists = async ({ user_id }) => (await sessionPool().query(USER_EXISTS_QUERY, [user_id])).rows.length === 1;
module.exports.checkSessionStore = async () => { await querySession('startup-probe-that-is-not-a-valid-session'); };
module.exports.closePool = async () => { if (pool) { await pool.end(); pool = undefined; } };
