# Deployment Guide

Production deployment guide for Smart Vial Backend.

---

## Pre-Deployment Checklist

Before deploying to production:

- [ ] Change JWT_SECRET to strong random value
- [ ] Change DEVICE_API_KEY to strong random value  
- [ ] Update MONGO_URI to production database
- [ ] Configure CORS_ORIGINS for production domains
- [ ] Set NODE_ENV=production
- [ ] Remove .env from repository (add to .gitignore)
- [ ] Enable HTTPS/SSL
- [ ] Set up database backups
- [ ] Configure monitoring and logging
- [ ] Test all APIs thoroughly
- [ ] Document deployment process
- [ ] Create rollback plan

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

**Last Updated**: February 2, 2026
