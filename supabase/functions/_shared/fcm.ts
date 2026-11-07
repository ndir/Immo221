// Envoi de notifications via Firebase Cloud Messaging (API HTTP v1).
// Authentification par compte de service : JWT signé RS256 avec WebCrypto, échangé contre un jeton OAuth2.

export type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const b64url = (data: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\\n|\s/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0)).buffer as ArrayBuffer;
  return crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

/** JWT signé pour l'échange OAuth2 (exporté pour les tests). */
export async function signServiceJwt(sa: ServiceAccount, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64url(sig)}`;
}

let cached: { token: string; exp: number } | null = null;

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await signServiceJwt(sa, now),
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`oauth ${res.status}: ${JSON.stringify(json).slice(0, 200)}`);
  cached = { token: json.access_token, exp: now + Number(json.expires_in ?? 3600) };
  return cached.token;
}

export type PushMessage = {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  priority?: "normal" | "high";
};

export type PushResult = { ok: true } | { ok: false; unregistered: boolean; error: string };

export async function sendPush(sa: ServiceAccount, m: PushMessage): Promise<PushResult> {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await accessToken(sa)}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token: m.token,
        notification: { title: m.title, body: m.body },
        data: m.data ?? {},
        android: {
          priority: m.priority === "high" ? "HIGH" : "NORMAL",
          notification: { channel_id: "dekk_alerts", sound: "default" },
        },
        apns: { payload: { aps: { sound: "default" } } },
      },
    }),
  });
  if (res.ok) return { ok: true };
  const text = await res.text();
  return { ok: false, unregistered: res.status === 404 || text.includes("UNREGISTERED"), error: `${res.status} ${text.slice(0, 300)}` };
}

export function loadServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return null;
  const sa = JSON.parse(raw);
  return { project_id: sa.project_id, client_email: sa.client_email, private_key: sa.private_key };
}
