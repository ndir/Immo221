// Accès au serveur pour la page web : Supabase en production, données fictives en démonstration.

const TERMINAL = ["found", "removed", "expired"];

/** Message lisible à partir d'une erreur Supabase / fonction. */
export function friendlyError(e) {
  const code = (e && (e.code || e.message || e.error)) || String(e);
  const map = {
    request_not_found: "Demande introuvable.",
    invalid_visibility: "Durée de visibilité invalide.",
    transaction_required: "Précisez s'il s'agit d'une location, d'une colocation, d'un achat ou d'un terrain.",
    zone_required: "Indiquez au moins un quartier ou une ville.",
    invalid_budget: "Le budget minimum dépasse le budget maximum.",
    owner_not_in_contacts: "Cet offreur ne vous a pas contacté.",
  };
  for (const [k, v] of Object.entries(map)) if (String(code).includes(k)) return v;
  if (/Invalid phone|phone/i.test(code)) return "Numéro invalide.";
  if (/Token has expired|invalid|otp/i.test(code)) return "Code incorrect ou expiré.";
  if (/fetch|network|Failed/i.test(code)) return "Connexion impossible. Vérifiez votre réseau et réessayez.";
  return "Une erreur est survenue. Réessayez.";
}

// ---------------------------------------------------------------------------
// Supabase
// ---------------------------------------------------------------------------
async function supabaseBackend(cfg) {
  const { createClient } = await import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm");
  const sb = createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true },
  });
  const must = ({ data, error }) => {
    if (error) throw error;
    return data;
  };

  return {
    demo: false,
    async session() {
      const { data } = await sb.auth.getSession();
      return data.session;
    },
    async sendCode(phone) {
      must(await sb.auth.signInWithOtp({ phone }));
    },
    async verifyCode(phone, token, name) {
      const data = must(await sb.auth.verifyOtp({ phone, token, type: "sms" }));
      if (name) {
        await sb.from("profiles").update({ display_name: name }).eq("id", data.user.id);
      }
      return data.session;
    },
    async zones() {
      return must(await sb.from("zones").select("id, name, city, region").order("city").order("name"));
    },
    async appSettings() {
      return must(await sb.from("app_settings").select("free_mode").single());
    },
    async uploadAndProcess(blob, mime, durationS) {
      const { data: { user } } = await sb.auth.getUser();
      if (!user) throw new Error("not_authenticated");
      const id = crypto.randomUUID();
      const ext = mime.includes("webm") ? "webm" : mime.includes("ogg") ? "ogg" : "mp4";
      const path = `${user.id}/${id}.${ext}`;
      must(await sb.storage.from("voice-requests").upload(path, blob, { contentType: mime, upsert: false }));
      must(await sb.from("requests").insert({
        id, audio_path: path, source: "web", audio_duration_s: Math.max(1, Math.min(180, Math.round(durationS))),
      }));
      return await this.process(id);
    },
    async process(id) {
      const { data, error } = await sb.functions.invoke("process-voice", { body: { request_id: id } });
      if (error) {
        let detail = null;
        try { detail = await error.context.json(); } catch { /* ignore */ }
        const e = new Error(detail?.message || "process_failed");
        e.userMessage = detail?.message;
        throw e;
      }
      return data;
    },
    async publish(id, f) {
      return must(await sb.rpc("publish_request", {
        p_request_id: id,
        p_transaction: f.transaction,
        p_property: f.property,
        p_zone_ids: f.zone_ids,
        p_zone_free_text: f.zone_free_text,
        p_budget_min: f.budget_min,
        p_budget_max: f.budget_max,
        p_budget_period: f.budget_period,
        p_bedrooms_min: f.bedrooms_min,
        p_furnished: f.furnished,
        p_move_in: f.move_in,
        p_summary: f.summary,
        p_visibility_days: f.visibility_days,
        p_is_urgent: f.is_urgent,
        p_user_edited: f.user_edited,
      }));
    },
    async myRequests() {
      return must(await sb.from("requests")
        .select("id, status, summary, transaction, property, zone_ids, zone_free_text, budget_max, budget_period, contacts_count, max_contacts, listen_count, expires_at, created_at")
        .not("status", "in", "(uploaded,processing)")
        .order("created_at", { ascending: false }).limit(20));
    },
    async contacts(requestId) {
      return must(await sb.from("my_request_contacts").select("*").eq("request_id", requestId).order("created_at"));
    },
    async extend(id, days = 15) { return must(await sb.rpc("extend_request", { p_request_id: id, p_days: days })); },
    async close(id, ownerId, rating) {
      return must(await sb.rpc("close_request", { p_request_id: id, p_helped_owner: ownerId || null, p_rating: rating || null }));
    },
    async remove(id) { return must(await sb.rpc("remove_request", { p_request_id: id })); },
    async signOut() { await sb.auth.signOut(); },
    terminal: TERMINAL,
  };
}

// ---------------------------------------------------------------------------
// Démonstration (aucun appel réseau)
// ---------------------------------------------------------------------------
function demoBackend() {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const zones = [
    { id: 1, name: "Mermoz", city: "Dakar", region: "Dakar" },
    { id: 2, name: "Sacré-Cœur", city: "Dakar", region: "Dakar" },
    { id: 3, name: "Point E", city: "Dakar", region: "Dakar" },
    { id: 4, name: "Almadies", city: "Dakar", region: "Dakar" },
    { id: 5, name: "Parcelles Assainies", city: "Dakar", region: "Dakar" },
    { id: 6, name: "Thiès", city: "Thiès", region: "Thiès" },
    { id: 7, name: "Saly", city: "Mbour", region: "Thiès" },
    { id: 8, name: "Saint-Louis", city: "Saint-Louis", region: "Saint-Louis" },
    { id: 9, name: "Ziguinchor", city: "Ziguinchor", region: "Ziguinchor" },
  ];
  let session = null;
  const store = { requests: [] };
  return {
    demo: true,
    async session() { return session; },
    async sendCode() { await wait(500); },
    async verifyCode(phone, code) {
      await wait(500);
      if (code !== "123456") throw new Error("invalid otp");
      session = { user: { id: "demo", phone } };
      return session;
    },
    async zones() { return zones; },
    async appSettings() { return { free_mode: true }; },
    async uploadAndProcess() {
      await wait(1800);
      const r = {
        id: "demo-1", status: "draft",
        transcript: "Salam, dama bëgg un appartement deux chambres vers Mermoz ou Sacré-Cœur, budget 300 mille par mois maximum, pour le mois prochain.",
        transaction: "location", property: "appartement", zone_ids: [1, 2], zone_free_text: null,
        budget_min: null, budget_max: 300000, budget_period: "mois", bedrooms_min: 2, furnished: null,
        move_in: "le mois prochain", is_urgent: false,
        summary: "Appartement 2 ch. à Mermoz ou Sacré-Cœur, max 300 000 F/mois, pour le mois prochain",
        contacts_count: 0, max_contacts: 5, listen_count: 0, created_at: new Date().toISOString(),
      };
      store.requests = [r];
      return { request: r, zones: zones.filter((z) => r.zone_ids.includes(z.id)) };
    },
    async process() { return this.uploadAndProcess(); },
    async publish(id, f) {
      await wait(600);
      const r = store.requests.find((x) => x.id === id);
      Object.assign(r, f, { status: "published", expires_at: new Date(Date.now() + f.visibility_days * 86400000).toISOString() });
      setTimeout(() => { r.listen_count = 4; r.contacts_count = 2; }, 1500);
      return r;
    },
    async myRequests() { return store.requests.filter((r) => r.status !== "draft"); },
    async contacts() {
      return [
        { owner_id: "o1", owner_name: "Immo Sacré-Cœur", owner_role: "agency", is_verified: true, rating_avg: 4.7, rating_count: 23, created_at: new Date().toISOString() },
        { owner_id: "o2", owner_name: "Moussa D.", owner_role: "broker", is_verified: false, rating_avg: 4.2, rating_count: 8, created_at: new Date().toISOString() },
      ];
    },
    async extend(id, days = 15) {
      const r = store.requests.find((x) => x.id === id);
      r.expires_at = new Date(new Date(r.expires_at).getTime() + days * 86400000).toISOString();
      r.status = "published";
    },
    async close(id) { store.requests.find((x) => x.id === id).status = "found"; },
    async remove(id) { store.requests.find((x) => x.id === id).status = "removed"; },
    async signOut() { session = null; },
    terminal: TERMINAL,
  };
}

export async function createBackend(cfg) {
  const demo = cfg.demo || new URLSearchParams(location.search).has("demo") || cfg.supabaseUrl.includes("VOTRE-PROJET");
  return demo ? demoBackend() : supabaseBackend(cfg);
}
