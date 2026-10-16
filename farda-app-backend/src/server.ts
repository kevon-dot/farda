import express, { type ErrorRequestHandler } from 'express';
import helmet from 'helmet';
import apiRouter from './routes/apiRouter';
import { createBillingWebhookRouter } from './billing/routes';

const app = express();
app.disable('x-powered-by');
app.use(helmet());
app.use(createBillingWebhookRouter());
app.use(express.json({ limit: '64kb' }));
app.use(express.urlencoded({ extended: false, limit: '16kb' }));
app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.use('/api', apiRouter);
app.use((_req, res) => res.status(404).json({ error: 'Route not found', code: 'not_found' }));
const errors: ErrorRequestHandler = (error, _req, res, _next) => {
  if (res.headersSent) return;
  const status = error?.type === 'entity.too.large' ? 413 : error instanceof SyntaxError ? 400 : 503;
  // Avoid default Express HTML stacks and provider/SQL/health-data payloads.
  res.status(status).json({ error: status === 413 ? 'Request is too large' : status === 400 ? 'Invalid JSON request' : 'This service is temporarily unavailable', code: status === 503 ? 'temporarily_unavailable' : 'invalid_request' });
};
app.use(errors);
export default app;
