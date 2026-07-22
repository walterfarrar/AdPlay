import "dotenv/config";
import path from "node:path";
import { fileURLToPath } from "node:url";
import Fastify from "fastify";
import cors from "@fastify/cors";
import fastifyStatic from "@fastify/static";
import { getDb } from "./db/index.js";
import { authRoutes } from "./routes/auth.js";
import { gameRoutes } from "./routes/game.js";
import { adRoutes } from "./routes/ads.js";
import { adminRoutes, withdrawalRoutes } from "./routes/withdrawals.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function main() {
  getDb();

  const app = Fastify({ logger: true });
  await app.register(cors, { origin: true });

  await app.register(authRoutes);
  await app.register(gameRoutes);
  await app.register(adRoutes);
  await app.register(withdrawalRoutes);
  await app.register(adminRoutes);

  app.get("/health", async () => ({
    ok: true,
    adProvider: process.env.AD_PROVIDER ?? "mock",
  }));

  await app.register(fastifyStatic, {
    root: path.join(__dirname, "../admin"),
    prefix: "/admin/",
  });

  const port = Number(process.env.PORT ?? 8787);
  await app.listen({ port, host: "0.0.0.0" });
  console.log(`AdPlay API on http://localhost:${port}`);
  console.log(`Admin UI: http://localhost:${port}/admin/`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
