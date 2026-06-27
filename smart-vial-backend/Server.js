require('dotenv').config()
const express = require('express');
const mongoose = require('mongoose');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');

const config = require('./config/config');
const { sanitizeRequest } = require('./middleware/sanitize');

const app = express();

// ============================================
// Security headers (#36)
// ============================================
app.use(helmet());

// ============================================
// CORS allowlist (#36)
// ============================================
// Origins come from config (CORS_ORIGINS env, comma-separated). No wildcard is
// used on credentialed/authed routes. Requests with no Origin header (native
// devices, curl, server-to-server) are allowed so device ingestion keeps working.
const allowedOrigins = config.cors.origins;
app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      return callback(new Error(`Origin ${origin} not allowed by CORS`));
    },
    credentials: true,
  })
);

// ============================================
// Body parsing with size limit (#36)
// ============================================
app.use(express.json({ limit: process.env.JSON_BODY_LIMIT || '100kb' }));

// ============================================
// NoSQL operator-injection protection (#37)
// ============================================
// Strips $-prefixed and dotted keys from body/query/params on every request.
app.use(sanitizeRequest);

// ============================================
// Rate limiting (#36)
// ============================================
// A general limiter for the whole API, plus stricter limiters on the high-risk
// ingestion and auth-bearing surfaces. All return HTTP 429.
const generalLimiter = rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.maxRequests,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});

// Ingestion is hit by every device frequently but per-IP abuse should still be
// bounded. Use a tighter per-window cap on a short window.
const ingestionLimiter = rateLimit({
  windowMs: parseInt(process.env.INGEST_RATE_LIMIT_WINDOW_MS) || 60 * 1000, // 1 minute
  max: parseInt(process.env.INGEST_RATE_LIMIT_MAX) || 120, // 2 req/s sustained
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many ingestion requests, please slow down.' },
});

// Auth-bearing user/caregiver routes: stricter to blunt credential stuffing.
const authLimiter = rateLimit({
  windowMs: parseInt(process.env.AUTH_RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.AUTH_RATE_LIMIT_MAX) || 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests to authenticated routes, please try again later.' },
});

app.use(generalLimiter);

// Routes
const ingestionRoutes = require('./routes/ingestionAPI');
app.use('/api/ingest', ingestionLimiter, ingestionRoutes);

const caregiverRoutes = require('./routes/caregiverAPI');
app.use('/api/caregiver', authLimiter, caregiverRoutes);

const userRoutes = require('./routes/userAPI');
app.use('/api/user', authLimiter, userRoutes);

// ============================================
// JSON error handler (#36)
// ============================================
// Return clean JSON for CORS rejections, oversized bodies, and malformed JSON
// instead of leaking HTML stack traces.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err && /not allowed by CORS/.test(err.message || '')) {
    return res.status(403).json({ error: 'Origin not allowed by CORS' });
  }
  if (err && (err.type === 'entity.too.large' || err.status === 413)) {
    return res.status(413).json({ error: 'Request body too large' });
  }
  if (err && (err.type === 'entity.parse.failed' || err.status === 400)) {
    return res.status(400).json({ error: 'Malformed JSON body' });
  }
  console.error('Unhandled error:', err && err.message);
  return res.status(500).json({ error: 'Internal Server Error' });
});

const PORT = process.env.PORT || 5000;

// Don't start listening (or open DB) when imported by tests.
if (require.main === module) {
    mongoose.connect(process.env.MONGO_URI)
        .then(() => console.log('MongoDB connected'))
        .catch(err => console.log('MongoDB connection error:', err));

    app.listen(PORT, () => console.log(`server running on port ${PORT}`));
}

module.exports = app;
