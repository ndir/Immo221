// process-voice : transcrit le vocal d'une demande et prépare la fiche (statut « draft »).
// Appelée par l'app ou la page web juste après l'envoi de l'audio :
//   POST /functions/v1/process-voice  { "request_id": "<uuid>" }  (en-tête Authorization de l'utilisateur)
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";
import {
  buildTranscriptionPrompt, fallbackSummary, matchZones, sanitizeExtraction, type Zone,
} from "../_shared/extract.ts";
import { extract, transcribe } from "../_shared/openai.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const TRANSCRIBE_MODEL = Deno.env.get("OPENAI_TRANSCRIBE_MODEL") ?? "gpt-4o-mini-transcribe";
const EXTRACT_MODEL = Deno.env.get("OPENAI_EXTRACT_MODEL") ?? "gpt-4o-mini";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!OPENAI_KEY) return json({ error: "openai_not_configured" }, 500);

  // 1. Qui appelle ?
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "not_authenticated" }, 401);

  let requestId: string;
  try {
    requestId = String((await req.json()).request_id ?? "");
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(requestId)) return json({ error: "invalid_request_id" }, 400);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // 2. La demande appartient-elle à l'appelant et est-elle à traiter ?
  const { data: request, error: loadError } = await admin
    .from("requests").select("*").eq("id", requestId).maybeSingle();
  if (loadError) return json({ error: "db_error" }, 500);
  if (!request || request.seeker_id !== user.id) return json({ error: "request_not_found" }, 404);
  if (request.status === "draft" || request.status === "published") {
    return json({ request, zones: [] }); // déjà traitée : idempotent
  }
  if (!["uploaded", "failed"].includes(request.status)) return json({ error: "request_not_processable" }, 409);

  await admin.from("requests").update({ status: "processing", ai_error: null }).eq("id", requestId);

  try {
    // 3. Audio + référentiel des zones
    const { data: audio, error: dlError } = await admin.storage.from("voice-requests").download(request.audio_path);
    if (dlError || !audio) throw new Error("audio_introuvable");
    if (audio.size > 5 * 1024 * 1024) throw new Error("audio_trop_lourd");

    const { data: zoneRows } = await admin.from("zones").select("id, name, city, region, aliases");
    const zones = (zoneRows ?? []) as Zone[];

    // 4. Transcription
    const filename = request.audio_path.split("/").pop() ?? "vocal.m4a";
    const { text: transcript, model: usedModel } = await transcribe(
      audio, filename, buildTranscriptionPrompt(zones), OPENAI_KEY, TRANSCRIBE_MODEL,
    );
    if (transcript.length < 3) throw new Error("vocal_vide");

    // 5. Extraction structurée + nettoyage
    const raw = await extract(transcript, zones, OPENAI_KEY, EXTRACT_MODEL);
    const fields = sanitizeExtraction(raw);
    const { ids, unmatched } = matchZones(fields.zones, fields.city, zones);
    const zoneNames = ids.map((id) => zones.find((z) => z.id === id)!.name);

    const update = {
      status: "draft",
      transcript,
      transcript_lang: "fr-wo",
      ai_raw: { extraction: raw, transcribe_model: usedModel, extract_model: EXTRACT_MODEL },
      ai_confidence: fields.confidence,
      transaction: fields.transaction,
      property: fields.property,
      zone_ids: ids,
      zone_free_text: unmatched.length ? unmatched.join(", ") : null,
      budget_min: fields.budget_min,
      budget_max: fields.budget_max,
      budget_period: fields.budget_period,
      bedrooms_min: fields.bedrooms_min,
      furnished: fields.furnished,
      move_in: fields.move_in,
      is_urgent: fields.is_urgent,
      summary: fields.summary || fallbackSummary(fields, zoneNames),
    };
    const { data: saved, error: saveError } = await admin
      .from("requests").update(update).eq("id", requestId).select("*").single();
    if (saveError) throw new Error("enregistrement_impossible");

    return json({ request: saved, zones: ids.map((id) => zones.find((z) => z.id === id)) });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error("process-voice", requestId, message);
    await admin.from("requests").update({ status: "failed", ai_error: message.slice(0, 500) }).eq("id", requestId);
    const userMessage =
      message === "vocal_vide" ? "Nous n'avons rien entendu. Réessayez en parlant près du micro."
      : message === "audio_trop_lourd" ? "Le vocal est trop long (1 min 30 maximum)."
      : "Le traitement a échoué. Réessayez dans un instant.";
    return json({ error: message, message: userMessage }, 502);
  }
});
