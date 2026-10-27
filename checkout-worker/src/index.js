// Connecting Captions key delivery (Paddle Billing).
//
// Paddle calls POST /webhook with `transaction.completed` when a purchase is paid.
// This Worker checks the Paddle-Signature header, looks up the buyer's email,
// signs a personal license key in the format CommercialLicense.swift verifies,
// and emails it to the buyer through Resend. One key per transaction.
//
// Token: base64url(json) + "." + base64url(ed25519 signature over the json bytes)
// The app checks it offline with the public key baked into CommercialLicense.swift.

const PRODUCT_ID = "connectingCaptions";
const PERSONAL_SEATS = 2;
const PERSONAL_EXPIRES = "2099-12-31";
const SIGNATURE_TOLERANCE_SECONDS = 300;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }
    if (request.method === "POST" && url.pathname === "/webhook") {
      return handleWebhook(request, env);
    }
    return new Response("Not found", { status: 404 });
  },
};

export async function handleWebhook(request, env, now = Date.now()) {
  const raw = await request.text();
  const header = request.headers.get("Paddle-Signature") || "";
  if (!env.PADDLE_WEBHOOK_SECRET || !(await verifyPaddleSignature(raw, header, env.PADDLE_WEBHOOK_SECRET, now))) {
    return json({ error: "bad signature" }, 401);
  }

  let event;
  try {
    event = JSON.parse(raw);
  } catch {
    return json({ error: "bad json" }, 400);
  }

  if (event?.event_type !== "transaction.completed") {
    return json({ ignored: event?.event_type || "unknown" });
  }

  const txn = event.data || {};
  const transactionId = String(txn.id || "");
  if (txn.status !== "completed" || !transactionId) {
    return json({ ignored: `status ${txn.status}` });
  }

  const personalPrices = splitList(env.PERSONAL_PRICE_IDS);
  const items = Array.isArray(txn.items) ? txn.items : [];
  const isPersonal = items.some((item) => {
    const price = item?.price || {};
    return personalPrices.includes(String(price.id || item?.price_id || "")) || price.custom_data?.license === "personal";
  });
  if (!isPersonal) {
    // Work licenses, SLA and the MDM package are issued by hand after an invoice.
    return json({ ignored: "not a personal key" });
  }

  // Paddle retries a webhook until it gets a 2xx. Keep one key per transaction.
  const store = env.ISSUED_KEYS;
  if (store && (await store.get(`txn:${transactionId}`))) {
    return json({ ok: true, duplicate: true });
  }

  const email = await customerEmail(env, txn.customer_id);
  if (!email) {
    // 5xx so Paddle retries; the lookup may succeed on the next attempt.
    return json({ error: "could not find the buyer's email" }, 502);
  }

  const major = parseInt(env.KEY_MAJOR || "1", 10);
  const issued = utcDay(new Date(now));
  const token = await issuePersonalToken({ email, major, issued, privateKeyBase64: env.LICENSE_PRIVATE_KEY });

  const sent = await sendKeyEmail(env, { email, token, major, reference: txn.invoice_number || transactionId });
  if (!sent.ok) {
    return json({ error: "email failed", detail: sent.detail }, 502);
  }

  if (store) {
    await store.put(`txn:${transactionId}`, JSON.stringify({ email, token, issued }));
  }
  return json({ ok: true });
}

// Paddle-Signature: ts=1671552777;h1=<hex hmac-sha256 of "ts:rawBody">
// During secret rotation Paddle can send more than one h1.
export async function verifyPaddleSignature(raw, header, secret, now = Date.now()) {
  const parts = Object.create(null);
  const signatures = [];
  for (const piece of header.split(";")) {
    const [key, value] = piece.split("=").map((s) => (s || "").trim());
    if (key === "h1") signatures.push(value.toLowerCase());
    else if (key) parts[key] = value;
  }
  const ts = parseInt(parts.ts, 10);
  if (!Number.isFinite(ts) || signatures.length === 0) return false;
  if (Math.abs(now / 1000 - ts) > SIGNATURE_TOLERANCE_SECONDS) return false;
  const expected = await hmacHex(secret, `${ts}:${raw}`);
  return signatures.some((sig) => timingSafeEqual(expected, sig));
}

async function customerEmail(env, customerId) {
  if (!customerId || !env.PADDLE_API_KEY) return null;
  const base = env.PADDLE_ENVIRONMENT === "sandbox" ? "https://sandbox-api.paddle.com" : "https://api.paddle.com";
  const response = await fetch(`${base}/customers/${encodeURIComponent(customerId)}`, {
    headers: { Authorization: `Bearer ${env.PADDLE_API_KEY}` },
  });
  if (!response.ok) return null;
  const body = await response.json().catch(() => null);
  const email = String(body?.data?.email || "").trim();
  return email.includes("@") ? email : null;
}

export async function issuePersonalToken({ email, major, issued, privateKeyBase64 }) {
  if (!privateKeyBase64) throw new Error("LICENSE_PRIVATE_KEY is not set");
  if (!Number.isInteger(major) || major < 1) throw new Error("KEY_MAJOR must be 1 or higher");
  // Same fields the app reads. Keys are sorted like the issue script's JSONEncoder.
  const wire = {
    expires: PERSONAL_EXPIRES,
    issued,
    major,
    org: email,
    personal: true,
    product: PRODUCT_ID,
    seats: PERSONAL_SEATS,
  };
  const payload = new TextEncoder().encode(JSON.stringify(wire));
  const key = await importPrivateKey(privateKeyBase64);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, key, payload));
  return `${base64url(payload)}.${base64url(signature)}`;
}

// The private key is the raw 32-byte Ed25519 seed in standard Base64, the same
// value scripts/issue-commercial-license.sh reads. WebCrypto needs it as PKCS#8.
async function importPrivateKey(base64) {
  const seed = fromBase64(base64.trim());
  if (seed.length !== 32) throw new Error("LICENSE_PRIVATE_KEY must be 32 bytes");
  const prefix = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20]);
  const pkcs8 = new Uint8Array(prefix.length + seed.length);
  pkcs8.set(prefix);
  pkcs8.set(seed, prefix.length);
  return crypto.subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, false, ["sign"]);
}

async function sendKeyEmail(env, { email, token, major, reference }) {
  if (!env.RESEND_API_KEY || !env.EMAIL_FROM) {
    return { ok: false, detail: "RESEND_API_KEY or EMAIL_FROM is not set" };
  }
  const text = [
    "Thanks for buying Connecting Captions.",
    "",
    "Your personal license key:",
    "",
    token,
    "",
    "To use it, open Connecting Captions, go to Settings → General, and paste the key.",
    `It covers you on up to two of your own Macs, with updates for version ${major}.`,
    "The key is checked on your Mac. The app never sends it anywhere.",
    "",
    `Order ${reference}`,
    "Questions: reply to this email.",
  ].join("\n");

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.EMAIL_FROM,
      to: [email],
      reply_to: env.REPLY_TO || undefined,
      subject: "Your Connecting Captions license key",
      text,
    }),
  });
  if (!response.ok) {
    return { ok: false, detail: `${response.status} ${await response.text()}` };
  }
  return { ok: true };
}

async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  return [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function utcDay(date) {
  return date.toISOString().slice(0, 10);
}

function splitList(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64(base64) {
  const binary = atob(base64);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
