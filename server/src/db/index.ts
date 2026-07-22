import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let db: DatabaseSync | null = null;

export function getDb(): DatabaseSync {
  if (db) return db;

  const dbPath = process.env.DATABASE_PATH ?? "./data/adplay.db";
  const resolved = path.isAbsolute(dbPath)
    ? dbPath
    : path.resolve(process.cwd(), dbPath);

  fs.mkdirSync(path.dirname(resolved), { recursive: true });

  db = new DatabaseSync(resolved);
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA foreign_keys = ON;");

  db.exec(schema);

  // Additive migrations for existing DBs
  const cols = db
    .prepare("PRAGMA table_info(game_state)")
    .all() as { name: string }[];
  const names = new Set(cols.map((c) => c.name));
  if (!names.has("tap_strength_boost_until")) {
    db.exec("ALTER TABLE game_state ADD COLUMN tap_strength_boost_until TEXT");
  }
  if (!names.has("tap_strength_boost_amount")) {
    db.exec(
      "ALTER TABLE game_state ADD COLUMN tap_strength_boost_amount REAL NOT NULL DEFAULT 0",
    );
  }

  return db;
}
