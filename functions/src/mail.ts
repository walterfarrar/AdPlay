import nodemailer from "nodemailer";
import { signAdminAction, type AdminEmailAction } from "./adminAuth";

const NOTIFY_TO = process.env.ADMIN_NOTIFY_EMAIL || "admin@fullyversed.com";

export type WithdrawNotifyPayload = {
  userId: string;
  withdrawalId: string;
  amountSats: number;
  bolt11: string;
  satsBalanceAfter: number;
  satsEarnedToday: number;
  adEventCount: number;
  adsUsedThisCycle: number;
  ledgerCreditCount: number;
  createdAt: string;
};

function gmailReady(): boolean {
  const user = (process.env.GMAIL_USER || "").trim();
  const pass = (process.env.GMAIL_APP_PASSWORD || "").trim().replace(/\s+/g, "");
  if (!user || !pass) return false;
  if (pass.startsWith("REPLACE_WITH_")) return false;
  return true;
}

function actionBaseUrl(): string {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "adplay-sats";
  return `https://us-central1-${project}.cloudfunctions.net/adminEmailAction`;
}

function actionUrl(
  action: AdminEmailAction,
  userId: string,
  withdrawalId: string,
): string {
  const base = actionBaseUrl();
  const signed = signAdminAction(action, userId, withdrawalId);
  return (
    `${base}?action=${action}&userId=${encodeURIComponent(userId)}` +
    `&withdrawalId=${encodeURIComponent(withdrawalId)}&exp=${signed.exp}&sig=${signed.sig}`
  );
}

function buildLinks(userId: string, withdrawalId: string) {
  return {
    paidUrl: actionUrl("paid", userId, withdrawalId),
    rejectUrl: actionUrl("reject", userId, withdrawalId),
    refundUrl: actionUrl("refund", userId, withdrawalId),
  };
}

function htmlBody(
  p: WithdrawNotifyPayload,
  paidUrl: string,
  rejectUrl: string,
  refundUrl: string,
): string {
  const bolt = escapeHtml(p.bolt11);
  return `<!DOCTYPE html>
<html><body style="font-family:Segoe UI,Arial,sans-serif;line-height:1.45;color:#111">
  <h2 style="margin:0 0 12px">AdPlay redeem request</h2>
  <p style="margin:0 0 16px"><strong>${p.amountSats}</strong> sats pending payout</p>
  <table style="border-collapse:collapse;font-size:14px;margin-bottom:20px">
    <tr><td style="padding:4px 12px 4px 0;color:#555">Withdrawal</td><td><code>${escapeHtml(p.withdrawalId)}</code></td></tr>
    <tr><td style="padding:4px 12px 4px 0;color:#555">User</td><td><code>${escapeHtml(p.userId)}</code></td></tr>
    <tr><td style="padding:4px 12px 4px 0;color:#555">Created</td><td>${escapeHtml(p.createdAt)}</td></tr>
    <tr><td style="padding:4px 12px 4px 0;color:#555">Balance after hold</td><td>${p.satsBalanceAfter} sats</td></tr>
    <tr><td style="padding:4px 12px 4px 0;color:#555">Earned today</td><td>${p.satsEarnedToday} sats</td></tr>
    <tr><td style="padding:4px 12px 4px 0;color:#555">Ad events (all time)</td><td>${p.adEventCount}</td></tr>
    <tr><td style="padding:4px 12px 4px 0;color:#555">Ads used this cycle</td><td>${p.adsUsedThisCycle}</td></tr>
    <tr><td style="padding:4px 12px 4px 0;color:#555">Ledger sat credits</td><td>${p.ledgerCreditCount}</td></tr>
  </table>
  <p style="margin:0 0 8px;font-size:13px;color:#555">BOLT11</p>
  <pre style="white-space:pre-wrap;word-break:break-all;background:#f4f4f4;padding:12px;border-radius:6px;font-size:12px">${bolt}</pre>
  <p style="margin:24px 0 8px">Choose one:</p>
  <p style="margin:0 0 16px">
    <a href="${paidUrl}" style="display:inline-block;background:#0a7a3e;color:#fff;text-decoration:none;padding:12px 18px;border-radius:6px;font-weight:600;margin:0 8px 8px 0">Mark paid</a>
    <a href="${rejectUrl}" style="display:inline-block;background:#8a1f1f;color:#fff;text-decoration:none;padding:12px 18px;border-radius:6px;font-weight:600;margin:0 8px 8px 0">Reject</a>
    <a href="${refundUrl}" style="display:inline-block;background:#555;color:#fff;text-decoration:none;padding:12px 18px;border-radius:6px;font-weight:600;margin:0 8px 8px 0">Refund</a>
  </p>
  <ul style="margin:0;padding-left:18px;font-size:13px;color:#555">
    <li><strong>Mark paid</strong> — you sent the Lightning payment</li>
    <li><strong>Reject</strong> — deny (keep held sats; use for fishy requests)</li>
    <li><strong>Refund</strong> — return held sats to the player</li>
  </ul>
  <p style="margin-top:20px;font-size:12px;color:#777">Links expire in 7 days. Verify ad events / ledger in Firebase if anything looks off.</p>
</body></html>`;
}

function textBody(
  p: WithdrawNotifyPayload,
  paidUrl: string,
  rejectUrl: string,
  refundUrl: string,
): string {
  return [
    `AdPlay redeem: ${p.amountSats} sats`,
    `Withdrawal: ${p.withdrawalId}`,
    `User: ${p.userId}`,
    `Created: ${p.createdAt}`,
    `Balance after hold: ${p.satsBalanceAfter}`,
    `Earned today: ${p.satsEarnedToday}`,
    `Ad events: ${p.adEventCount}`,
    `Ads this cycle: ${p.adsUsedThisCycle}`,
    `Ledger credits: ${p.ledgerCreditCount}`,
    "",
    `BOLT11:`,
    p.bolt11,
    "",
    `Mark paid: ${paidUrl}`,
    `Reject (keep sats): ${rejectUrl}`,
    `Refund (return sats): ${refundUrl}`,
  ].join("\n");
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Best-effort notify; never throws to the caller. */
export async function notifyWithdrawalRequest(p: WithdrawNotifyPayload): Promise<void> {
  if (!gmailReady()) {
    console.warn(
      "Skipping withdraw email: set GMAIL_USER and GMAIL_APP_PASSWORD secrets",
    );
    return;
  }
  const { paidUrl, rejectUrl, refundUrl } = buildLinks(p.userId, p.withdrawalId);
  const gmailUser = (process.env.GMAIL_USER || "").trim();
  const gmailPass = (process.env.GMAIL_APP_PASSWORD || "").trim().replace(/\s+/g, "");
  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: gmailUser,
      pass: gmailPass,
    },
  });
  await transporter.sendMail({
    from: `AdPlay <${gmailUser}>`,
    to: NOTIFY_TO,
    subject: `AdPlay redeem: ${p.amountSats} sats`,
    text: textBody(p, paidUrl, rejectUrl, refundUrl),
    html: htmlBody(p, paidUrl, rejectUrl, refundUrl),
  });
}
