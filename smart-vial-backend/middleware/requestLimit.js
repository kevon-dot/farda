function requestLimit({ max = 180, windowMs = 60000, now = Date.now, maxKeys = 10000 } = {}) {
  const buckets = new Map();
  return (req, res, next) => {
    const time = now();
    const key = req.ip || 'unknown';
    let bucket = buckets.get(key);
    if (!bucket || bucket.expires <= time) {
      if (buckets.size >= maxKeys) {
        for (const [oldKey, old] of buckets) if (old.expires <= time) buckets.delete(oldKey);
        if (!buckets.has(key) && buckets.size >= maxKeys) return res.status(503).json({ error: 'Service temporarily busy' });
      }
      bucket = { count: 0, expires: time + windowMs };
      buckets.set(key, bucket);
    }
    bucket.count++;
    if (bucket.count > max) {
      res.set('Retry-After', String(Math.max(1, Math.ceil((bucket.expires - time) / 1000))));
      return res.status(429).json({ error: 'Too many requests', code: 'rate_limited' });
    }
    return next();
  };
}

module.exports = { requestLimit };
