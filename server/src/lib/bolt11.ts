/**
 * Lightweight BOLT11 checks (no full crypto decode).
 * Accepts mainnet (lnbc) and testnet (lntb / lntbs).
 */
export function validateBolt11(invoice: string): { ok: true } | { ok: false; error: string } {
  const raw = invoice.trim().toLowerCase();
  if (!raw) return { ok: false, error: "Invoice is empty" };
  if (raw.includes(" ")) return { ok: false, error: "Invoice must be a single string" };
  if (!(raw.startsWith("lnbc") || raw.startsWith("lntb") || raw.startsWith("lntbs"))) {
    return { ok: false, error: "Invoice must start with lnbc, lntb, or lntbs" };
  }
  if (raw.length < 50) return { ok: false, error: "Invoice looks too short" };
  if (raw.length > 2000) return { ok: false, error: "Invoice looks too long" };
  if (!/^[a-z0-9]+$/.test(raw)) {
    return { ok: false, error: "Invoice has invalid characters" };
  }
  return { ok: true };
}
