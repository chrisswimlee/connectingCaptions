# Key delivery

Paddle sells the personal key ($49, price `pri_01m5vhcet3gp2wxbdz61p4awm4`). When a purchase completes, Paddle calls this Cloudflare Worker with `transaction.completed`. The Worker checks the `Paddle-Signature` header, looks up the buyer's email through the Paddle API, signs a personal key in the format `CommercialLicense.swift` verifies, and emails it through Resend. One key per transaction, even when Paddle retries.

The key matches what `scripts/issue-commercial-license.sh --personal --buyer EMAIL` prints: `product: connectingCaptions`, `personal: true`, `seats: 2`, `expires: 2099-12-31`, `major` from `KEY_MAJOR`, and the buyer email as `org`. The app checks it offline.

Work licenses, the written SLA and the MDM package are sold by Paddle invoice. The Worker ignores them. Issue those keys by hand after the invoice is paid.

Run the tests with `npm test`.

## Set up, in order

### 1. License key pair

The private key must match the public key in `CommercialLicense.swift`. It lives in `~/.config/connectingcaptions/commercial-license.ed25519` (mode 600). Keep a copy in a password manager.

### 2. Paddle

1. The personal key price exists. Make the `SHOWHN` discount: flat $20 off, restricted to the personal price, ending on the last day of launch week.
2. Developer tools → Authentication → create an API key with **Customers: Read**. Save it for step 4.
3. Checkout settings → set the default payment link to the pricing page, and approve that domain.

### 3. Resend

1. Sign up at resend.com and add the domain `local-host.ai`.
2. Add the DNS records Resend shows at the place that hosts the domain's DNS, then press Verify.
3. API Keys → create a key with sending access.

### 4. Cloudflare Worker

From this folder on your Mac:

```bash
npx wrangler login
npx wrangler kv namespace create ISSUED_KEYS     # paste the id into wrangler.toml
npx wrangler secret put LICENSE_PRIVATE_KEY < ~/.config/connectingcaptions/commercial-license.ed25519
npx wrangler secret put PADDLE_API_KEY
npx wrangler secret put RESEND_API_KEY
npx wrangler deploy
```

`deploy` prints the Worker's address, like `https://connecting-captions-keys.YOURNAME.workers.dev`.

### 5. Paddle webhook

Paddle → Developer tools → Notifications → New destination:

- URL: the Worker address with `/webhook` on the end
- Events: `transaction.completed`

Paddle shows a **secret key** for that destination. Then:

```bash
npx wrangler secret put PADDLE_WEBHOOK_SECRET
```

### 6. Test before launch

Paddle has a separate sandbox account. To test end to end, make the same product there, set `PADDLE_ENVIRONMENT = "sandbox"` and the sandbox price ID, use sandbox API and webhook secrets, deploy, and buy with Paddle's test card. Paste the emailed key in Connecting Captions → Settings → General. It should say **Personal license**. Then switch everything back to production and deploy.

### 7. Go live

Paste the checkout link into both pricing pages and publish both sites before the app release that links to them.

## Refunds

A key is checked offline, so a refund cannot switch it off.
