# Deployment Guide

Production deployment guide for Smart Vial Backend.

---

## Pre-Deployment Checklist

Before deploying to production:

- [ ] Set `MONGO_URI` to the production MongoDB (device/event data)
- [ ] Set `DATABASE_URL` to the shared PostgreSQL / better-auth database (MUST match the main app)
- [ ] Set `BETTER_AUTH_URL` to the deployed base URL (used for better-auth origin checks)
- [ ] Set `DEVICE_SECRET_ENC_KEY` to a 64-char hex (32-byte) master key (encrypts device secrets at rest)
- [ ] Set `TYME_SYNC_TOLERANCE_SECONDS` (default 300) for device timestamp freshness
- [ ] Configure `CORS_ORIGINS` for production domains (allowlist, no wildcard on authed routes)
- [ ] Tune rate limits if needed (`RATE_LIMIT_*`, `INGEST_RATE_LIMIT_*`, `AUTH_RATE_LIMIT_*`)
- [ ] Set `NODE_ENV=production`
- [ ] Remove `.env` from repository (add to `.gitignore`)
- [ ] Enable HTTPS/SSL
- [ ] Set up database backups (MongoDB and PostgreSQL)
- [ ] Configure monitoring and logging
- [ ] Test all APIs thoroughly
- [ ] Document deployment process
- [ ] Create rollback plan

> There is no `JWT_SECRET` or `DEVICE_API_KEY` to rotate anymore — user auth is
> better-auth (PostgreSQL) and device auth is per-device HMAC. The legacy
> `JWT_*`/`DEVICE_API_KEY` config keys still exist for backward compatibility but are
> **not** used on the auth paths.

---

## Deployment Options

### Option 1: Traditional VPS (DigitalOcean, Linode, AWS EC2)

**Pros**:
- Full control
- Cost-effective
- Flexible configuration

**Cons**:
- Manual setup required
- Need to manage server maintenance

### Option 2: Platform as a Service (Heroku, Render, Railway)

**Pros**:
- Easy deployment
- Auto-scaling
- Managed infrastructure

**Cons**:
- Higher cost
- Less control

### Option 3: Serverless (AWS Lambda, Google Cloud Functions)

**Pros**:
- Pay per use
- Auto-scaling

**Cons**:
- Cold start latency
- Requires refactoring

**Recommended**: Option 2 (PaaS) for quick deployment, Option 1 for cost efficiency.

---

## Deployment: Heroku (PaaS)

### Prerequisites

- Heroku account
- Heroku CLI installed



## Database Setup

### MongoDB Atlas (Recommended)

1. Create account at https://www.mongodb.com/atlas
2. Create new project
3. Build a cluster (free tier available)
4. Create database user
5. Whitelist IP addresses (0.0.0.0/0 for all, or specific IPs)
6. Get connection string
7. Add to `.env`:

```env
MONGO_URI=mongodb+srv://username:password@cluster.mongodb.net/smartvial?retryWrites=true&w=majority
```

### Enable Backups

Atlas provides automatic backups in paid tiers. For free tier:

1. Use mongodump periodically
2. Store backups in S3 or similar

### PostgreSQL (better-auth identity store)

This service also requires access to the **same PostgreSQL database the main app
uses for better-auth**. Set `DATABASE_URL` to that connection string — do not stand
up a separate identity database, or sessions issued by the main app won't validate
here.

```env
DATABASE_URL=postgres://username:password@host:5432/database
BETTER_AUTH_URL=https://your-server.com
```


---

### Connection Pooling

MongoDB connection is already optimized with Mongoose.

---

## Scaling

### Horizontal Scaling

1. **Deploy multiple instances**
2. **Use load balancer** (AWS ALB, Nginx)
3. **Session management**: Use Redis for shared sessions

### Vertical Scaling

Upgrade server resources:
- More CPU cores
- More RAM
- Faster disk (SSD)

### Database Scaling

- Enable MongoDB sharding
- Use read replicas
- Consider caching layer (Redis)

---

**Last Updated**: June 27, 2026
