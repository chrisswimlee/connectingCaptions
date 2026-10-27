// Run: npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import { webcrypto, createHmac, generateKeyPairSync, verify as nodeVerify } from "node:crypto";
import worker, { issuePersonalToken, verifyPaddleSignature } from "../src/index.js";

if (!globalThis.crypto) globalThis.crypto = webcrypto;

const SECRET = "pdl_ntfset_test_secret";
const PERSONAL_PRICE = "pri_01m5vhcet3gp2wxbdz61p4awm4";
const WORK_PRICE = "pri_01m5vkr4dtw8baqxrbqzngy6vc";
const { privateKey, publicKey } = generateKeyPairSync("ed25519");
const PRIVATE_B64 = Buffer.from(privateKey.export({ format: "der", type: "pkcs8" }).subarray(16)).toString("base64");

function env(extra = {}) {
  const kv = new Map();
  return {
    PADDLE_WEBHOOK_SECRET: SECRET,
    PADDLE_API_KEY: "pdl_live_apikey_test",
    LICENSE_PRIVATE_KEY: PRIVATE_B64,
    PERSONAL_PRICE_IDS: PERSONAL_PRICE,
    RESEND_API_KEY: "re_test",
    EMAIL_FROM: "Connecting Captions <keys@example.com>",
    KEY_MAJOR: "1",
    ISSUED_KEYS: { get: async (k) => kv.get(k) ?? null, put: async (k, v) => void kv.set(k, v) },
    ...extra,
  };
}

function transaction({ price = PERSONAL_PRICE, customData = null, status = "completed", event = "transaction.completed", id = "txn_01abc" } = {}) {
  return JSON.stringify({
    event_id: "evt_01",
    event_type: event,
    data: {
      id,
      status,
      customer_id: "ctm_01buyer",
      invoice_number: "325-10001",
      items: [{ price: { id: price, custom_data: customData }, quantity: 1 }],
    },
  });
}

function request(body, { secret = SECRET, ts = Math.floor(Date.now() / 1000) } = {}) {
  const h1 = createHmac("sha256", secret).update(`${ts}:${body}`).digest("hex");
  return new Request("https://keys.example/webhook", {
    method: "POST",
    headers: { "Paddle-Signature": `ts=${ts};h1=${h1}`, "Content-Type": "application/json" },
    body,
  });
}

let emails = [];
let customerLookups = 0;
let resendStatus = 200;
globalThis.fetch = async (url, init = {}) => {
  if (String(url).includes("/customers/")) {
    customerLookups++;
    assert.equal(init.headers.Authorization, "Bearer pdl_live_apikey_test");
    return new Response(JSON.stringify({ data: { id: "ctm_01buyer", email: "ada@example.com" } }), { status: 200 });
  }
  if (resendStatus !== 200) return new Response("down", { status: resendStatus });
  emails.push(JSON.parse(init.body));
  return new Response("{}", { status: 200 });
};

function reset() {
  emails = [];
  customerLookups = 0;
  resendStatus = 200;
}

function tokenFrom(text) {
  return text.split("\n").find((line) => /^[\w-]+\.[\w-]+$/.test(line));
}

test("a completed personal purchase emails a key the public key verifies", async () => {
  reset();
  const res = await worker.fetch(request(transaction()), env());
  assert.equal(res.status, 200);
  assert.equal(emails.length, 1);
  assert.deepEqual(emails[0].to, ["ada@example.com"]);
  const [payload, signature] = tokenFrom(emails[0].text).split(".");
  const bytes = Buffer.from(payload, "base64url");
  assert.ok(nodeVerify(null, bytes, publicKey, Buffer.from(signature, "base64url")));
  const wire = JSON.parse(bytes);
  assert.deepEqual(
    { product: wire.product, personal: wire.personal, seats: wire.seats, major: wire.major, org: wire.org, expires: wire.expires },
    { product: "connectingCaptions", personal: true, seats: 2, major: 1, org: "ada@example.com", expires: "2099-12-31" },
  );
  assert.match(emails[0].text, /Order 325-10001/);
});

test("custom data license=personal also counts as a personal purchase", async () => {
  reset();
  await worker.fetch(request(transaction({ price: "pri_other", customData: { license: "personal" } })), env());
  assert.equal(emails.length, 1);
});

test("a bad or stale signature is rejected and nothing is sent", async () => {
  reset();
  assert.equal((await worker.fetch(request(transaction(), { secret: "wrong" }), env())).status, 401);
  const old = Math.floor(Date.now() / 1000) - 3600;
  assert.equal((await worker.fetch(request(transaction(), { ts: old }), env())).status, 401);
  assert.equal(emails.length, 0);
});

test("a retried webhook does not send a second key", async () => {
  reset();
  const e = env();
  await worker.fetch(request(transaction()), e);
  const again = await worker.fetch(request(transaction()), e);
  assert.equal(again.status, 200);
  assert.equal(emails.length, 1);
});

test("work licenses, other events and unfinished transactions are ignored", async () => {
  reset();
  for (const body of [
    transaction({ price: WORK_PRICE, customData: { license: "work" } }),
    transaction({ event: "transaction.paid" }),
    transaction({ status: "billed" }),
  ]) {
    assert.equal((await worker.fetch(request(body), env())).status, 200);
  }
  assert.equal(emails.length, 0);
  assert.equal(customerLookups, 0);
});

test("an email failure returns 502 so Paddle retries, then the retry sends once", async () => {
  reset();
  const e = env();
  resendStatus = 500;
  assert.equal((await worker.fetch(request(transaction()), e)).status, 502);
  resendStatus = 200;
  assert.equal((await worker.fetch(request(transaction()), e)).status, 200);
  assert.equal(emails.length, 1);
});

test("signature check accepts any h1 during secret rotation", async () => {
  const ts = Math.floor(Date.now() / 1000);
  const body = "{}";
  const good = createHmac("sha256", SECRET).update(`${ts}:${body}`).digest("hex");
  assert.equal(await verifyPaddleSignature(body, `ts=${ts};h1=${"0".repeat(64)};h1=${good}`, SECRET), true);
  assert.equal(await verifyPaddleSignature(body, `ts=${ts};h1=${"0".repeat(64)}`, SECRET), false);
});

test("KEY_MAJOR sets the version a key covers", async () => {
  const token = await issuePersonalToken({ email: "a@b.co", major: 2, issued: "2026-10-26", privateKeyBase64: PRIVATE_B64 });
  assert.equal(JSON.parse(Buffer.from(token.split(".")[0], "base64url")).major, 2);
});
