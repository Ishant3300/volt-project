'use strict';

// In-memory stand-in for the equity mongoose models (no MongoDB in unit tests).
// Documents are real mongoose documents of the real schemas (defaults, validation,
// toJSON transform); only storage and the handful of query shapes the equity
// controller uses are faked.

const mongoose = require('mongoose');

const str = (v) => (v === undefined || v === null ? null : String(v));

function matches(doc, q) {
  return Object.entries(q || {}).every(([k, want]) => {
    const have = doc[k];
    if (want && typeof want === 'object' && !(want instanceof mongoose.Types.ObjectId) && !(want instanceof Date)) {
      if (Array.isArray(want.$in)) return want.$in.map(String).includes(str(have));
      if (Array.isArray(want.$nin)) return !want.$nin.map(String).includes(str(have));
      if (want.$regex !== undefined) return new RegExp(want.$regex, want.$options || '').test(String(have ?? ''));
    }
    return str(have) === str(want);
  });
}

function sortDocs(list, spec) {
  if (!spec) return list;
  const keys = Object.entries(spec);
  return [...list].sort((a, b) => {
    for (const [k, dir] of keys) {
      const x = a[k] instanceof Date ? a[k].getTime() : a[k];
      const y = b[k] instanceof Date ? b[k].getTime() : b[k];
      if (x < y) return -dir;
      if (x > y) return dir;
    }
    return 0;
  });
}

function leanOf(doc, select) {
  const o = doc.toObject();
  if (typeof select === 'string') for (const f of select.split(/\s+/)) if (f.startsWith('-')) delete o[f.slice(1)];
  return o;
}

function makeFake(Real) {
  const store = new Map();
  let clock = Date.parse('2026-11-01T00:00:00Z');

  const attach = (doc) => {
    doc.save = async () => {
      await doc.validate();
      if (!doc.createdAt && Real.schema.options.timestamps) doc.createdAt = new Date(clock += 1000);
      store.set(String(doc._id), doc);
      return doc;
    };
    return doc;
  };

  const query = (run) => {
    const state = { select: null, sort: null, lean: false, limit: 0 };
    const chain = {
      select(s) { state.select = s; return chain; },
      sort(s) { state.sort = s; return chain; },
      lean() { state.lean = true; return chain; },
      limit(n) { state.limit = n; return chain; },
      session() { return chain; },
      then(resolve, reject) {
        try {
          const out = run(state);
          return Promise.resolve(out).then(resolve, reject);
        } catch (e) {
          return Promise.reject(e).then(resolve, reject);
        }
      },
    };
    return chain;
  };

  const all = () => [...store.values()];

  const fake = {
    store,
    reset() { store.clear(); },
    async create(data) {
      const doc = attach(new Real(data));
      return doc.save();
    },
    find(q) {
      return query((s) => {
        let list = sortDocs(all().filter((d) => matches(d, q)), s.sort);
        if (s.limit) list = list.slice(0, s.limit);
        return s.lean ? list.map((d) => leanOf(d, s.select)) : list;
      });
    },
    findOne(q) {
      return query((s) => {
        const d = all().find((x) => matches(x, q)) || null;
        if (!d) return null;
        return s.lean ? leanOf(d, s.select) : d;
      });
    },
    findById(id) {
      return fake.findOne({ _id: id });
    },
    async exists(q) {
      const d = all().find((x) => matches(x, q));
      return d ? { _id: d._id } : null;
    },
    async countDocuments(q) {
      return all().filter((d) => matches(d, q)).length;
    },
    async distinct(field, q) {
      return [...new Set(all().filter((d) => matches(d, q)).map((d) => d[field]))];
    },
    async deleteOne(q) {
      const d = all().find((x) => matches(x, q));
      if (d) store.delete(String(d._id));
      return { deletedCount: d ? 1 : 0 };
    },
    async updateMany(q, update) {
      const hits = all().filter((d) => matches(d, q));
      for (const d of hits) { Object.assign(d, update.$set || {}); await d.save(); }
      return { modifiedCount: hits.length };
    },
    async bulkWrite(ops) {
      for (const op of ops) {
        const { filter, update, upsert } = op.updateOne;
        let d = all().find((x) => matches(x, filter));
        if (!d && upsert) d = attach(new Real({ ...filter }));
        if (!d) continue;
        Object.assign(d, update.$set || {});
        await d.save();
      }
      return { ok: 1 };
    },
    async aggregate(pipeline) {
      let rows = all();
      for (const stage of pipeline) {
        if (stage.$match) rows = rows.filter((d) => matches(d, stage.$match));
        if (stage.$group) {
          const field = stage.$group._id.replace(/^\$/, '');
          const groups = new Map();
          for (const d of rows) groups.set(str(d[field]), (groups.get(str(d[field])) || 0) + 1);
          rows = [...groups].map(([id, n]) => ({ _id: id, n }));
        }
      }
      return rows;
    },
  };
  return fake;
}

module.exports = { makeFake };
