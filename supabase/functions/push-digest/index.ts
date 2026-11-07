// push-digest : envoie en une seule notification les push mis en attente
// (heures calmes, mode « résumé », plafond quotidien). Planifiée à 7 h 05 et 18 h (pg_cron).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { json, safeEqual } from "../_shared/http.ts";
import { loadServiceAccount, sendPush } from "../_shared/fcm.ts";
import { digestText, isQuietTime } from "../_shared/push_rules.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const SECRET = Deno.env.get("WEBHOOK_SECRET");

Deno.serve(async (req) => {
  if (!safeEqual(req.headers.get("x-webhook-secret"), SECRET)) return json({ error: "forbidden" }, 403);
  if (isQuietTime(new Date())) return json({ skipped: "quiet_hours" });

  const sa = loadServiceAccount();
  const { data: pending } = await admin
    .from("notifications")
    .select("id, user_id, type, title, body, data")
    .eq("push_status", "deferred")
    .gte("created_at", new Date(Date.now() - 2 * 86_400_000).toISOString())
    .order("created_at", { ascending: true })
    .limit(5000);

  const byUser = new Map<string, NonNullable<typeof pending>>();
  for (const n of pending ?? []) byUser.set(n.user_id, [...(byUser.get(n.user_id) ?? []), n]);

  let sent = 0;
  for (const [userId, items] of byUser) {
    const ids = items.map((i) => i.id);
    const { data: profile } = await admin.from("profiles").select("fcm_token").eq("id", userId).maybeSingle();
    if (!sa || !profile?.fcm_token) {
      await admin.from("notifications").update({ push_status: "skipped" }).in("id", ids);
      continue;
    }
    const { title, body } = digestText(items);
    const result = await sendPush(sa, {
      token: profile.fcm_token,
      title,
      body,
      data: {
        type: items.length === 1 ? items[0].type : "digest",
        request_id: items.length === 1 ? String(items[0].data?.request_id ?? "") : "",
      },
    });
    if (!result.ok && result.unregistered) await admin.from("profiles").update({ fcm_token: null }).eq("id", userId);
    await admin.from("notifications").update({ push_status: result.ok ? "sent" : "failed" }).in("id", ids);
    if (result.ok) sent++;
  }
  // Les différés plus anciens que 2 jours ne valent plus la peine d'être envoyés
  await admin.from("notifications").update({ push_status: "skipped" })
    .eq("push_status", "deferred").lt("created_at", new Date(Date.now() - 2 * 86_400_000).toISOString());

  return json({ users: byUser.size, sent });
});
