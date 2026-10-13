// send-notifications: sends the rows queued in notification_outbox as push notifications
// through Firebase Cloud Messaging, one per registered phone of each recipient.
//
// Called by the database when rows are queued, and every five minutes for anything a failed
// run left behind. It takes no input and only drains the queue, so it needs no sign-in.
//
// Secret FCM_SERVICE_ACCOUNT: the Firebase service account key (JSON). Until it is set the
// function does nothing and rows wait in the queue.

import { createClient } from "jsr:@supabase/supabase-js@2";

// A notification older than this is no longer news: it is marked done without sending.
const MAX_AGE_MS = 24 * 60 * 60 * 1000;

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
type Row = { id: string; recipient_id: string; title: string; body: string; data: Record<string, unknown>; created_at: string };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlText = (text: string) => b64url(new TextEncoder().encode(text));

// A short-lived Google access token for FCM, from the service account's key.
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64urlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64urlText(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`token ${res.status}: ${await res.text()}`);
  return (await res.json()).access_token;
}

type Outcome = "sent" | "gone" | "retry" | "failed";

async function send(sa: ServiceAccount, token: string, pushToken: string, row: Row): Promise<Outcome> {
  const data: Record<string, string> = { notification_id: row.id };
  for (const [k, v] of Object.entries(row.data ?? {})) data[k] = String(v);
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token: pushToken,
        notification: { title: row.title, body: row.body },
        data,
        android: { priority: "high" },
      },
    }),
  });
  if (res.ok) return "sent";
  const text = await res.text();
  // The app was uninstalled or the token replaced: forget this phone.
  if (res.status === 404 || text.includes("UNREGISTERED") || (res.status === 400 && /registration token/i.test(text))) {
    return "gone";
  }
  console.error(`fcm ${res.status}: ${text}`);
  // Throttled or down: try again later. Anything else would fail again, so give up on it.
  return res.status === 429 || res.status >= 500 ? "retry" : "failed";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return json({ configured: false });
  const sa = JSON.parse(raw) as ServiceAccount;

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: rows, error } = await admin.rpc("claim_notifications", { p_limit: 200 });
  if (error) return json({ error: error.message }, 500);
  if (!rows?.length) return json({ sent: 0 });

  const recipients = [...new Set((rows as Row[]).map((r) => r.recipient_id))];
  const { data: devices, error: devError } = await admin
    .from("devices")
    .select("person_id, push_token")
    .in("person_id", recipients);
  if (devError) return json({ error: devError.message }, 500);

  const token = await accessToken(sa);
  const gone = new Set<string>();
  let sent = 0;
  for (const row of rows as Row[]) {
    const stale = Date.now() - new Date(row.created_at).getTime() > MAX_AGE_MS;
    let reached = 0;
    let retry = false;
    if (!stale) {
      for (const d of devices ?? []) {
        if (d.person_id !== row.recipient_id || gone.has(d.push_token)) continue;
        const outcome = await send(sa, token, d.push_token, row);
        if (outcome === "sent") reached++;
        if (outcome === "gone") gone.add(d.push_token);
        if (outcome === "retry") retry = true;
      }
    }
    // A row waiting on a retry keeps its claim and is picked up again in five minutes.
    if (!retry || reached > 0) {
      await admin.from("notification_outbox").update({ sent_at: new Date().toISOString(), devices_reached: reached })
        .eq("id", row.id);
    }
    sent += reached;
  }
  if (gone.size) await admin.from("devices").delete().in("push_token", [...gone]);
  return json({ rows: rows.length, sent, removed_devices: gone.size });
});
