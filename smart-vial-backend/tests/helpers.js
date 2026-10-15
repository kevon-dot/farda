function response() {
  return { code: 200, headers: {}, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; }, set(key, value) { this.headers[key] = value; return this; } };
}
function query(value) {
  const promise = Promise.resolve(value);
  return { select() { return this; }, session() { return this; }, sort() { return this; }, limit() { return this; }, then: promise.then.bind(promise) };
}
function get(object, path) { return path.split('.').reduce((result, key) => result?.[key], object); }
function matches(object, filter) {
  return Object.entries(filter).every(([path, value]) => {
    if (path === '$or') return value.some(condition => matches(object, condition));
    if (path === '$expr') return value.$eq.map(item => get(object, item.slice(1))).reduce((a, b) => a === b);
    const actual = get(object, path);
    if (value && typeof value === 'object' && !(value instanceof Date)) {
      return Object.entries(value).every(([operation, operand]) => {
        if (operation === '$gt') return actual > operand;
        if (operation === '$gte') return actual >= operand;
        if (operation === '$lte') return actual <= operand;
        if (operation === '$type') return operand === 'date' ? actual instanceof Date : typeof actual === operand;
        return false;
      });
    }
    return value === null ? actual == null : actual === value;
  });
}
function assign(object, path, value, remove = false) {
  const keys = path.split('.');
  const leaf = keys.pop();
  let cursor = object;
  for (const key of keys) cursor = cursor[key] ||= {};
  if (remove) delete cursor[leaf]; else cursor[leaf] = value;
}
function fakeDevices(rows) {
  return {
    rows, updates: [],
    findOne(filter) { return query(structuredClone(rows.find(row => matches(row, filter)) || null)); },
    find(filter) { return query(structuredClone(rows.filter(row => matches(row, filter)))); },
    findOneAndUpdate(filter, update) {
      this.updates.push({ filter, update });
      const row = rows.find(item => matches(item, filter));
      if (!row) return query(null);
      for (const [path, value] of Object.entries(update.$set || {})) assign(row, path, value);
      for (const path of Object.keys(update.$unset || {})) assign(row, path, undefined, true);
      for (const [path, value] of Object.entries(update.$inc || {})) assign(row, path, (get(row, path) || 0) + value);
      return query(structuredClone(row));
    },
  };
}
module.exports = { response, query, matches, fakeDevices };
