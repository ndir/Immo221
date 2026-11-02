// Tests de la logique serveur (sans réseau).
// Lancer : node --experimental-strip-types --test supabase/tests/functions.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import {
  buildTranscriptionPrompt, fallbackSummary, matchZones, normalize, sanitizeExtraction, EXTRACTION_SCHEMA, type Zone,
} from "../functions/_shared/extract.ts";
import { decidePush, digestText, isQuietTime } from "../functions/_shared/push_rules.ts";
import { signServiceJwt } from "../functions/_shared/fcm.ts";

const zones: Zone[] = [
  { id: 1, name: "Mermoz", city: "Dakar", region: "Dakar", aliases: ["Pyrotechnie"] },
  { id: 2, name: "Sacré-Cœur", city: "Dakar", region: "Dakar", aliases: ["Sacre Coeur", "Sacré-Cœur 3"] },
  { id: 3, name: "Parcelles Assainies", city: "Dakar", region: "Dakar", aliases: ["Parcelles", "PA"] },
  { id: 4, name: "Thiès", city: "Thiès", region: "Thiès", aliases: ["Thies"] },
  { id: 5, name: "Saly", city: "Mbour", region: "Thiès", aliases: ["Saly Portudal"] },
  { id: 6, name: "Guédiawaye", city: "Guédiawaye", region: "Dakar", aliases: ["Golf"] },
];

test("normalize retire accents et ponctuation", () => {
  assert.equal(normalize("Sacré-Cœur"), "sacre coeur");
  assert.equal(normalize("  Thiès! "), "thies");
});

test("matchZones reconnaît noms, alias et phrases", () => {
  const r = matchZones(["Mermoz", "sacre coeur", "vers les Parcelles", "Kounoune"], "Dakar", zones);
  assert.deepEqual(r.ids, [1, 2, 3]);
  assert.deepEqual(r.unmatched, ["Kounoune"]);
});

test("matchZones utilise la ville si aucun quartier n'est cité", () => {
  assert.deepEqual(matchZones([], "Thies", zones).ids, [4]);
  assert.deepEqual(matchZones([], null, zones), { ids: [], unmatched: [] });
});

test("matchZones ne crée pas de doublons", () => {
  assert.deepEqual(matchZones(["Saly", "Saly Portudal"], "Mbour", zones).ids, [5]);
});

test("sanitizeExtraction borne et corrige la sortie du modèle", () => {
  const e = sanitizeExtraction({
    transaction: "location", property: "appartement", zones: ["Mermoz", "", 3],
    city: "Dakar", budget_min: null, budget_max: 300, budget_period: null,
    bedrooms_min: 2, furnished: "oui", move_in: "le mois prochain", is_urgent: true,
    summary: "Appartement 2 ch.", confidence: 1.7,
  });
  assert.equal(e.budget_max, 300000, "« 300 » pour une location = 300 mille");
  assert.equal(e.budget_period, "mois");
  assert.deepEqual(e.zones, ["Mermoz"]);
  assert.equal(e.furnished, null);
  assert.equal(e.confidence, 1);
  assert.equal(e.is_urgent, true);
});

test("sanitizeExtraction : terrain, montant total, valeurs invalides", () => {
  const e = sanitizeExtraction({
    transaction: "terrain", property: null, zones: ["Thiès"], budget_min: 30000000, budget_max: 25000000,
    budget_period: null, bedrooms_min: 99, transaction_extra: "x", summary: 42, confidence: "x",
  });
  assert.equal(e.property, "terrain");
  assert.equal(e.budget_min, 25000000);
  assert.equal(e.budget_max, 30000000);
  assert.equal(e.budget_period, "total");
  assert.equal(e.bedrooms_min, null);
  assert.equal(e.summary, "");
  assert.equal(e.confidence, 0.5);
});

test("sanitizeExtraction rejette les énumérations inconnues", () => {
  const e = sanitizeExtraction({ transaction: "vente", property: "chateau" });
  assert.equal(e.transaction, null);
  assert.equal(e.property, null);
  assert.equal(sanitizeExtraction(null).zones.length, 0);
});

test("le schéma JSON exige tous les champs (mode strict OpenAI)", () => {
  const props = Object.keys(EXTRACTION_SCHEMA.schema.properties).sort();
  assert.deepEqual([...EXTRACTION_SCHEMA.schema.required].sort(), props);
});

test("prompt de transcription : contexte et lieux", () => {
  const p = buildTranscriptionPrompt(zones);
  assert.match(p, /wolof/);
  assert.match(p, /Sacré-Cœur/);
});

test("résumé de secours lisible", () => {
  const e = sanitizeExtraction({ transaction: "location", property: "appartement", bedrooms_min: 2, budget_max: 300000 });
  assert.equal(fallbackSummary(e, ["Mermoz", "Sacré-Cœur"]), "Location appartement, 2 ch. à Mermoz ou Sacré-Cœur, max 300 000 F/mois");
});

test("heures calmes 22 h – 7 h (heure de Dakar)", () => {
  assert.equal(isQuietTime(new Date("2026-11-02T22:00:00Z")), true);
  assert.equal(isQuietTime(new Date("2026-11-02T06:59:00Z")), true);
  assert.equal(isQuietTime(new Date("2026-11-02T07:00:00Z")), false);
  assert.equal(isQuietTime(new Date("2026-11-02T21:59:00Z")), false);
});

test("règles d'envoi push", () => {
  const base = {
    type: "new_request", priority: "normal" as const, hasToken: true, instantAlerts: true,
    quietHours: true, sentLast24h: 0, dailyLimit: 10, now: new Date("2026-11-02T10:00:00Z"),
  };
  assert.equal(decidePush(base), "send");
  assert.equal(decidePush({ ...base, hasToken: false }), "skip");
  assert.equal(decidePush({ ...base, now: new Date("2026-11-02T23:30:00Z") }), "defer");
  assert.equal(decidePush({ ...base, now: new Date("2026-11-02T23:30:00Z"), quietHours: false }), "send");
  assert.equal(decidePush({ ...base, instantAlerts: false }), "defer");
  assert.equal(decidePush({ ...base, instantAlerts: false, priority: "high" }), "send");
  assert.equal(decidePush({ ...base, sentLast24h: 10 }), "defer");
  assert.equal(decidePush({ ...base, type: "owner_contacted", sentLast24h: 10 }), "send");
});

test("texte du résumé groupé", () => {
  assert.deepEqual(digestText([{ type: "new_request", title: "T", body: "B" }]), { title: "T", body: "B" });
  assert.equal(
    digestText([{ type: "new_request", title: "", body: "" }, { type: "new_request", title: "", body: "" }, { type: "found_thanks", title: "", body: "" }]).title,
    "2 nouvelles demandes dans vos zones",
  );
});

test("JWT Firebase signé RS256 et vérifiable", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  const jwt = await signServiceJwt(
    { project_id: "dekk-test", client_email: "push@dekk-test.iam.gserviceaccount.com", private_key: pem },
    1_800_000_000,
  );
  const [h, c, s] = jwt.split(".");
  const claims = JSON.parse(Buffer.from(c, "base64url").toString());
  assert.equal(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assert.equal(claims.exp - claims.iat, 3600);
  const ok = createVerify("RSA-SHA256").update(`${h}.${c}`).verify(publicKey, Buffer.from(s, "base64url"));
  assert.equal(ok, true);
});
