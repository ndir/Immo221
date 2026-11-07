// Logique pure (sans réseau) du traitement d'un vocal :
// prompt de transcription, schéma d'extraction, nettoyage et rapprochement des zones.
// Fonctionne sous Deno (Edge Functions) et sous Node 22+ (tests).

export type Zone = { id: number; name: string; city: string; region: string; aliases: string[] };

export const TRANSACTIONS = ["location", "colocation", "achat", "terrain"] as const;
export const PROPERTIES = [
  "chambre", "studio", "appartement", "maison", "villa", "terrain", "local_commercial", "autre",
] as const;

export type Extraction = {
  transaction: (typeof TRANSACTIONS)[number] | null;
  property: (typeof PROPERTIES)[number] | null;
  zones: string[];
  city: string | null;
  budget_min: number | null;
  budget_max: number | null;
  budget_period: "mois" | "total" | null;
  bedrooms_min: number | null;
  furnished: boolean | null;
  move_in: string | null;
  is_urgent: boolean;
  summary: string;
  confidence: number;
};

/** Minuscules, sans accents ni ponctuation : « Sacré-Cœur » → « sacre coeur ». */
export function normalize(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/œ/gi, "oe")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Contexte donné au modèle de transcription pour bien orthographier les lieux. */
export function buildTranscriptionPrompt(zones: Zone[]): string {
  const names = [...new Set(zones.map((z) => z.name))].slice(0, 120).join(", ");
  return (
    "Note vocale d'une personne au Sénégal qui cherche un logement ou un terrain, " +
    "en français, en wolof ou un mélange des deux. Montants en francs CFA " +
    "(« 300 mille », « 3 bâtons » = 3 millions, « 25 millions »). Lieux possibles : " + names + "."
  );
}

export const EXTRACTION_SCHEMA = {
  name: "demande_immobiliere",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: [
      "transaction", "property", "zones", "city", "budget_min", "budget_max", "budget_period",
      "bedrooms_min", "furnished", "move_in", "is_urgent", "summary", "confidence",
    ],
    properties: {
      transaction: { type: ["string", "null"], enum: [...TRANSACTIONS, null] },
      property: { type: ["string", "null"], enum: [...PROPERTIES, null] },
      zones: { type: "array", items: { type: "string" }, description: "Quartiers ou villes cités, tels que dits." },
      city: { type: ["string", "null"], description: "Ville principale (Dakar, Thiès, Mbour...)." },
      budget_min: { type: ["integer", "null"], description: "En FCFA, entier." },
      budget_max: { type: ["integer", "null"], description: "En FCFA, entier." },
      budget_period: { type: ["string", "null"], enum: ["mois", "total", null] },
      bedrooms_min: { type: ["integer", "null"] },
      furnished: { type: ["boolean", "null"] },
      move_in: { type: ["string", "null"], description: "Délai en clair : « immédiat », « le mois prochain »..." },
      is_urgent: { type: "boolean" },
      summary: { type: "string", description: "Une phrase en français, 120 caractères max." },
      confidence: { type: "number", description: "Entre 0 et 1." },
    },
  },
} as const;

export function buildExtractionMessages(transcript: string, zones: Zone[]) {
  const cities = [...new Set(zones.map((z) => z.city))].join(", ");
  return [
    {
      role: "system",
      content:
        "Tu extrais une demande immobilière à partir de la transcription d'un vocal (Sénégal, français et wolof). " +
        "Règles : montants en FCFA entiers (« 300 mille » = 300000, « 1 bâton » = 1000000, « 25 millions » = 25000000). " +
        "Location et colocation : budget par mois (budget_period = « mois ») ; achat et terrain : budget total. " +
        "« Chambre » en colocation = transaction colocation, bien chambre. Terrain à acheter = transaction terrain, bien terrain. " +
        "Ne devine pas : mets null si l'information n'est pas dite. is_urgent = vrai si la personne dit urgent, tout de suite, " +
        "immédiatement, cette semaine. summary : une phrase claire en français pour les offreurs, sans le nom ni le numéro de la personne. " +
        "Villes connues : " + cities + ".",
    },
    { role: "user", content: transcript },
  ];
}

const toInt = (v: unknown): number | null => {
  if (typeof v === "number" && Number.isFinite(v)) return Math.round(v);
  if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))) return Math.round(Number(v));
  return null;
};

/** Valide et borne la sortie du modèle (ne jamais lui faire confiance aveuglément). */
export function sanitizeExtraction(raw: unknown): Extraction {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const pick = <T extends readonly string[]>(v: unknown, allowed: T): T[number] | null =>
    typeof v === "string" && (allowed as readonly string[]).includes(v) ? (v as T[number]) : null;

  const transaction = pick(o.transaction, TRANSACTIONS);
  let property = pick(o.property, PROPERTIES);
  if (transaction === "terrain" && property === null) property = "terrain";

  let budgetMin = toInt(o.budget_min);
  let budgetMax = toInt(o.budget_max);
  if (budgetMin !== null && budgetMin <= 0) budgetMin = null;
  if (budgetMax !== null && budgetMax <= 0) budgetMax = null;
  // Montant manifestement dit « en mille » (ex. 300 au lieu de 300000) pour une location
  if (budgetMax !== null && budgetMax < 1000 && (transaction === "location" || transaction === "colocation")) {
    budgetMax *= 1000;
    if (budgetMin !== null && budgetMin < 1000) budgetMin *= 1000;
  }
  if (budgetMin !== null && budgetMax !== null && budgetMin > budgetMax) [budgetMin, budgetMax] = [budgetMax, budgetMin];

  let period = pick(o.budget_period, ["mois", "total"] as const);
  if (period === null && budgetMax !== null) {
    period = transaction === "achat" || transaction === "terrain" ? "total" : "mois";
  }

  let bedrooms = toInt(o.bedrooms_min);
  if (bedrooms !== null && (bedrooms < 0 || bedrooms > 20)) bedrooms = null;

  const zones = Array.isArray(o.zones)
    ? o.zones.filter((z): z is string => typeof z === "string" && z.trim() !== "").map((z) => z.trim()).slice(0, 6)
    : [];
  const city = typeof o.city === "string" && o.city.trim() ? o.city.trim() : null;
  const moveIn = typeof o.move_in === "string" && o.move_in.trim() ? o.move_in.trim().slice(0, 60) : null;
  const summary = typeof o.summary === "string" ? o.summary.trim().slice(0, 160) : "";
  const conf = typeof o.confidence === "number" ? Math.min(1, Math.max(0, o.confidence)) : 0.5;

  return {
    transaction,
    property,
    zones,
    city,
    budget_min: budgetMin,
    budget_max: budgetMax,
    budget_period: budgetMax === null && budgetMin === null ? null : period,
    bedrooms_min: bedrooms,
    furnished: typeof o.furnished === "boolean" ? o.furnished : null,
    move_in: moveIn,
    is_urgent: o.is_urgent === true,
    summary,
    confidence: Math.round(conf * 100) / 100,
  };
}

/**
 * Rapproche les lieux cités du référentiel (nom ou alias, sans accents).
 * Retourne les identifiants reconnus et le texte des lieux non reconnus.
 */
export function matchZones(spoken: string[], city: string | null, zones: Zone[]): { ids: number[]; unmatched: string[] } {
  const index = new Map<string, Zone[]>();
  for (const z of zones) {
    for (const label of [z.name, ...z.aliases]) {
      const key = normalize(label);
      if (!key) continue;
      index.set(key, [...(index.get(key) ?? []), z]);
    }
  }
  const ids: number[] = [];
  const unmatched: string[] = [];
  const cityKey = city ? normalize(city) : null;

  const candidates = spoken.length > 0 ? spoken : city ? [city] : [];
  for (const s of candidates) {
    const key = normalize(s);
    let found = index.get(key);
    if (!found) {
      // « vers Mermoz », « quartier Ngor » : on cherche un libellé contenu dans la phrase
      const hit = [...index.keys()]
        .filter((k) => k.length >= 3 && (` ${key} `).includes(` ${k} `))
        .sort((a, b) => b.length - a.length)[0];
      found = hit ? index.get(hit) : undefined;
    }
    if (!found || found.length === 0) {
      unmatched.push(s);
      continue;
    }
    // Homonymes : on préfère la zone de la ville citée
    const best = (cityKey && found.find((z) => normalize(z.city) === cityKey)) || found[0];
    if (!ids.includes(best.id)) ids.push(best.id);
  }
  return { ids, unmatched };
}

/** Résumé de secours si le modèle n'en fournit pas. */
export function fallbackSummary(e: Extraction, zoneNames: string[]): string {
  const parts: string[] = [];
  const t = e.transaction ? e.transaction[0].toUpperCase() + e.transaction.slice(1) : "Recherche";
  parts.push(`${t} ${e.property ? e.property.replace("_", " ") : "bien"}`);
  if (e.bedrooms_min) parts.push(`${e.bedrooms_min} ch.`);
  if (zoneNames.length) parts.push(`à ${zoneNames.join(" ou ")}`);
  if (e.budget_max) {
    parts.push(`max ${e.budget_max.toLocaleString("fr-FR").replace(/ | /g, " ")} F${e.budget_period === "mois" ? "/mois" : ""}`);
  }
  return parts.join(", ").replace(", à", " à");
}
