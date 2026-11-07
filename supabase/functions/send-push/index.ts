// send-push : envoie la notification push correspondant à une ligne de « notifications ».
// Déclenchée par un Database Webhook (INSERT sur public.notifications), avec l'en-tête
// x-webhook-secret = WEBHOOK_SECRET. Voir docs/MISE_EN_LIGNE.md.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { json, safeEqual } from "../_shared/http.ts";
import { loadServiceAccount, sendPush } from "../_shared/fcm.ts";
import { decidePush } from "../_shared/push_rules.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const SECRET = Deno.env.get("WEBHOOK_SECRET");

Deno.serve(async (req) => {
  if (!safeEqual(req.headers.get("x-webhook-secret"), SECRET)) return json({ error: "forbidden" }, 403);

  const payload = await req.json().catch(() => null);
  const n = payload?.record;
  if (payload?.type !== "INSERT" || !n?.id) return json({ ignored: true });

  const [{ data: profile }, { data: settings }, { data: app }, { count }] = await Promise.all([
    admin.from("profiles").select("fcm_token").eq("id", n.user_id).maybeSingle(),
    admin.from("user_settings").select("instant_alerts, quiet_hours").eq("user_id", n.user_id).maybeSingle(),
    admin.from("app_settings").select("push_daily_limit").single(),
    admin.from("notifications").select("id", { count: "exact", head: true })
      .eq("user_id", n.user_id).eq("push_status", "sent")
      .gte("created_at", new Date(Date.now() - 86_400_000).toISOString()),
  ]);

  const decision = decidePush({
    type: n.type,
    priority: n.priority === "high" ? "high" : "normal",
    hasToken: Boolean(profile?.fcm_token),
    instantAlerts: settings?.instant_alerts ?? true,
    quietHours: settings?.quiet_hours ?? true,
    sentLast24h: count ?? 0,
    dailyLimit: app?.push_daily_limit ?? 10,
    now: new Date(),
  });

  if (decision !== "send") {
    await admin.from("notifications").update({ push_status: decision === "defer" ? "deferred" : "skipped" }).eq("id", n.id);
    return json({ decision });
  }

  const sa = loadServiceAccount();
  if (!sa) {
    await admin.from("notifications").update({ push_status: "skipped" }).eq("id", n.id);
    return json({ decision: "skip", reason: "firebase_not_configured" });
  }

  const result = await sendPush(sa, {
    token: profile!.fcm_token,
    title: n.title,
    body: n.body,
    priority: n.priority,
    data: {
      notification_id: String(n.id),
      type: n.type,
      request_id: String(n.data?.request_id ?? ""),
    },
  });

  if (!result.ok && result.unregistered) {
    await admin.from("profiles").update({ fcm_token: null }).eq("id", n.user_id);
  }
  await admin.from("notifications").update({ push_status: result.ok ? "sent" : "failed" }).eq("id", n.id);
  return json({ decision, ok: result.ok, error: result.ok ? undefined : result.error });
});
