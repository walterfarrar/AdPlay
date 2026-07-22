import "dotenv/config";
import { getDb } from "./index.js";

getDb();
console.log("Database migrated.");
