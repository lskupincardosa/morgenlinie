// Morgenlinie Worker: serves the archive as static assets (see wrangler.jsonc) and sends
// a push notification to registered iPhones when a new edition appears in editions.json.
//
// Only /push/* reaches this code ("run_worker_first"); every other path is a static asset.
//
//   POST /push/register    {"token": "<hex APNs device token>", "env": "sandbox" | "production"}
//   POST /push/unregister  {"token": "<hex>"}
//   POST /push/test        Authorization: Bearer <ADMIN_TOKEN>; sends the newest edition now
//
// A cron trigger runs check() every 10 minutes: when editions.json names a newer date than the
// one last announced, every registered device gets one notification.
//
// Secrets (npx wrangler secret put …): APNS_KEY (the .p8 file), APNS_KEY_ID, ADMIN_TOKEN.
// Vars (wrangler.jsonc): APNS_TEAM_ID, APNS_TOPIC (the app's bundle ID).

const MAX_DEVICES = 50;
const LAST_KEY = "state:lastNotified";
const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
    try {
      if (pathname === "/push/register") return await register(request, env);
      if (pathname === "/push/unregister") return await unregister(request, env);
      if (pathname === "/push/test") return await test(request, env);
    } catch (err) {
      console.error(pathname, err);
      return json({ error: "internal error" }, 500);
    }
    return json({ error: "not found" }, 404);
  },

  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(check(env));
  },
};

// ---- Endpoints ----

async function register(request, env) {
  const body = await request.json().catch(() => null);
  const token = normalizeToken(body?.token);
  if (!token) return json({ error: "invalid token" }, 400);
  const apnsEnv = body?.env === "production" ? "production" : "sandbox";
  const key = `device:${token}`;
  if (!(await env.PUSH.get(key))) {
    const { keys } = await env.PUSH.list({ prefix: "device:", limit: MAX_DEVICES });
    if (keys.length >= MAX_DEVICES) return json({ error: "too many devices" }, 429);
  }
  await env.PUSH.put(key, JSON.stringify({ env: apnsEnv, registeredAt: new Date().toISOString() }));
  return json({ ok: true });
}

async function unregister(request, env) {
  const body = await request.json().catch(() => null);
  const token = normalizeToken(body?.token);
  if (!token) return json({ error: "invalid token" }, 400);
  await env.PUSH.delete(`device:${token}`);
  return json({ ok: true });
}

async function test(request, env) {
  const auth = request.headers.get("authorization") ?? "";
  if (!env.ADMIN_TOKEN || !timingSafeEqual(auth, `Bearer ${env.ADMIN_TOKEN}`)) {
    return json({ error: "unauthorized" }, 401);
  }
  const edition = await newestEdition(env);
  if (!edition) return json({ error: "no editions" }, 500);
  const results = await notifyAll(env, edition);
  return json({ edition: edition.date, results });
}

// ---- Cron ----

async function check(env) {
  const edition = await newestEdition(env);
  if (!edition) return;
  const last = await env.PUSH.get(LAST_KEY);
  // First run after deploy: remember the current edition instead of announcing an old one.
  if (!last) {
    await env.PUSH.put(LAST_KEY, edition.date);
    return;
  }
  if (edition.date <= last) return;
  if (!env.APNS_KEY || !env.APNS_KEY_ID) {
    console.warn("new edition", edition.date, "but APNs secrets are not set; not announcing yet");
    return;
  }
  // Mark first, so a slow or failing APNs call never leads to a second notification.
  await env.PUSH.put(LAST_KEY, edition.date);
  const results = await notifyAll(env, edition);
  console.log("notified", edition.date, JSON.stringify(results));
}

// ---- Editions ----

async function newestEdition(env) {
  const res = await env.ASSETS.fetch(new Request("https://assets.local/editions.json"));
  if (!res.ok) return null;
  const manifest = await res.json();
  const entry = manifest?.editions?.[0];
  if (!entry?.date || !entry?.path) return null;
  let headline = null;
  const page = await env.ASSETS.fetch(new Request(`https://assets.local/${entry.path}`));
  if (page.ok) headline = leadHeadline(await page.text());
  return { date: entry.date, topic: entry.topic ?? null, headline };
}

// Same rule as the app (EditionHTML.leadHeadline): the first <h3> after the lead story.
function leadHeadline(html) {
  const start = html.indexOf('<article class="story lead">');
  if (start < 0) return null;
  const m = /<h3[^>]*>([\s\S]*?)<\/h3>/.exec(html.slice(start));
  if (!m) return null;
  const text = decodeEntities(m[1].replace(/<[^>]+>/g, "")).split(/\s+/).filter(Boolean).join(" ");
  return text || null;
}

function decodeEntities(s) {
  const named = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all, e) => {
    if (e[0] === "#") {
      const code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : all;
    }
    return named[e.toLowerCase()] ?? all;
  });
}

const WEEKDAYS = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
const MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August",
  "September", "Oktober", "November", "Dezember"];

// "2026-11-18" → "Mittwoch, 18. November" (matches the app's local notification title).
function germanTitle(date) {
  const [y, m, d] = date.split("-").map(Number);
  const weekday = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return `${WEEKDAYS[weekday]}, ${d}. ${MONTHS[m - 1]}`;
}

// ---- APNs ----

async function notifyAll(env, edition) {
  const payload = {
    aps: {
      alert: {
        title: `Morgenlinie · ${germanTitle(edition.date)}`,
        ...(edition.topic ? { subtitle: edition.topic } : {}),
        body: edition.headline ?? "Die neue Ausgabe ist da.",
      },
      sound: "default",
      "thread-id": "editions",
    },
    date: edition.date,
  };
  const { keys } = await env.PUSH.list({ prefix: "device:", limit: MAX_DEVICES });
  if (keys.length === 0) return [];
  const jwt = await providerToken(env);
  const results = [];
  for (const { name } of keys) {
    const token = name.slice("device:".length);
    const record = JSON.parse((await env.PUSH.get(name)) ?? "{}");
    results.push(await sendToDevice(env, jwt, token, record, payload, edition.date));
  }
  return results;
}

async function sendToDevice(env, jwt, token, record, payload, date) {
  const preferred = record.env === "production" ? "production" : "sandbox";
  const other = preferred === "production" ? "sandbox" : "production";
  let res = await apnsPost(env, jwt, preferred, token, payload, date);
  // Xcode builds use the sandbox, TestFlight and App Store builds production. If the app
  // guessed wrong, the token is "bad" on one host and fine on the other.
  if (res.status === 400 && res.reason === "BadDeviceToken") {
    const retry = await apnsPost(env, jwt, other, token, payload, date);
    if (retry.status === 200) {
      await env.PUSH.put(`device:${token}`, JSON.stringify({ ...record, env: other }));
    }
    res = retry;
  }
  if (res.status === 410 || res.reason === "Unregistered") {
    await env.PUSH.delete(`device:${token}`);
  }
  return { device: token.slice(0, 8), status: res.status, reason: res.reason ?? null };
}

async function apnsPost(env, jwt, apnsEnv, token, payload, date) {
  const res = await fetch(`${HOSTS[apnsEnv]}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": `edition-${date}`,
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 12 * 3600),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  let reason;
  if (res.status !== 200) reason = (await res.json().catch(() => ({}))).reason ?? `HTTP ${res.status}`;
  return { status: res.status, reason };
}

// APNs provider token: an ES256 JWT signed with the .p8 key. Valid for an hour; Apple
// rejects tokens refreshed more often than every 20 minutes, so keep one per isolate.
let cachedToken = null;

async function providerToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.iat < 40 * 60) return cachedToken.jwt;
  const der = pemToDer(env.APNS_KEY);
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now }));
  const input = `${header}.${claims}`;
  // WebCrypto returns the raw r||s signature, which is exactly what JWT's ES256 expects.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  const jwt = `${input}.${b64url(sig)}`;
  cachedToken = { jwt, iat: now };
  return jwt;
}

function pemToDer(pem) {
  const base64 = (pem ?? "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(base64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function b64url(data) {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ---- Helpers ----

function normalizeToken(token) {
  if (typeof token !== "string") return null;
  const t = token.trim().toLowerCase();
  return /^[0-9a-f]{64,200}$/.test(t) ? t : null;
}

function timingSafeEqual(a, b) {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}
