CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  apple_sub TEXT UNIQUE,
  display_name TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS game_state (
  user_id TEXT PRIMARY KEY REFERENCES users(id),
  progress REAL NOT NULL DEFAULT 0,
  fill_rate REAL NOT NULL DEFAULT 0,
  auto_fill_until TEXT,
  speed_boost_until TEXT,
  speed_boost_amount REAL NOT NULL DEFAULT 0,
  tap_strength_boost_until TEXT,
  tap_strength_boost_amount REAL NOT NULL DEFAULT 0,
  taps_remaining INTEGER NOT NULL,
  tap_day TEXT NOT NULL,
  ads_used_today INTEGER NOT NULL DEFAULT 0,
  ads_day TEXT NOT NULL,
  sats_earned_today INTEGER NOT NULL DEFAULT 0,
  sats_day TEXT NOT NULL,
  last_ad_at TEXT,
  last_tick_at TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS ledger_entries (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  delta_sats INTEGER NOT NULL,
  reason TEXT NOT NULL,
  meta TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ledger_user ON ledger_entries(user_id, created_at);

CREATE TABLE IF NOT EXISTS ad_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  event_id TEXT NOT NULL UNIQUE,
  boost_type TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS withdrawals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  amount_sats INTEGER NOT NULL,
  bolt11 TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  admin_note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON withdrawals(status, created_at);
