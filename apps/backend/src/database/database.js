const mongoose = require('mongoose');

const connectDatabase = async () => {
  try {
    const conn = await mongoose.connect(process.env.MONGO_URI, {
      // Auto-create indexes defined in schemas
      autoIndex: true,
      // Auto-create collections when models are used
      autoCreate: true,
      // Previously unset (driver default: 100) — with heavy concurrent bulk
      // rollover/square-off plus normal trade traffic, an unbounded pool
      // lets a burst of slow operations exhaust connections rather than
      // queuing predictably. maxPoolSize caps that; minPoolSize keeps a few
      // warm so the first requests after idle time don't pay handshake cost.
      maxPoolSize: parseInt(process.env.MONGO_MAX_POOL_SIZE || '50', 10),
      minPoolSize: parseInt(process.env.MONGO_MIN_POOL_SIZE || '5', 10),
      // Fail fast instead of hanging indefinitely if MongoDB is unreachable
      // (network blip, DB restart) — a hung request holds up whatever
      // resources it acquired (sessions, the trade-write lease) for however
      // long the driver would otherwise wait with no timeout at all.
      serverSelectionTimeoutMS: 10000,
      socketTimeoutMS: 45000,
    });

    console.log(`MongoDB Connected: ${conn.connection.host}`);
    console.log(`Database: ${conn.connection.name}`);

    // Visibility into connection health after the initial connect succeeds —
    // there was no monitoring of drops/errors at all before this; a silent
    // disconnect just meant every subsequent query hung/failed with a
    // reason the runtime never actually reported.
    mongoose.connection.on('error', (err) => {
      console.error('❌ [MongoDB] Connection error:', err.message);
    });
    mongoose.connection.on('disconnected', () => {
      console.warn('⚠️  [MongoDB] Disconnected — the driver will attempt to reconnect automatically.');
    });
    mongoose.connection.on('reconnected', () => {
      console.log('✅ [MongoDB] Reconnected.');
    });
    
    // Skip index sync in production for faster startup (~3s saved).
    // Indexes only change during code deploys — run once manually after deploy
    // or set SYNC_INDEXES=true for that single restart.
    if (process.env.NODE_ENV === 'production' && process.env.SYNC_INDEXES !== 'true') {
      console.log('⏭️  Index sync skipped (production). Set SYNC_INDEXES=true to force.');
      return;
    }

    // Sync all models - ensures collections and indexes exist
    console.log('🔄 Syncing database models...');
    
    // Get all registered models
    const models = mongoose.modelNames();
    console.log(`   Found ${models.length} models: ${models.join(', ')}`);
    
    // Sync indexes for all models
    for (const modelName of models) {
      const model = mongoose.model(modelName);
      await model.syncIndexes();
      console.log(`   ✅ Synced indexes for ${modelName}`);
    }
    
    console.log('✅ Database sync complete');
    
  } catch (error) {
    console.error(`❌ Database connection error: ${error.message}`);
    process.exit(1);
  }
};

module.exports = connectDatabase;
