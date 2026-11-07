// Règles d'envoi des notifications push (logique pure, testable).

export type PushContext = {
  type: string;
  priority: "normal" | "high";
  hasToken: boolean;
  instantAlerts: boolean;   // réglage offreur
  quietHours: boolean;      // réglage « silence 22 h – 7 h »
  sentLast24h: number;
  dailyLimit: number;
  now: Date;                // heure de Dakar = UTC
};

export type PushDecision = "send" | "defer" | "skip";

/** Heure de Dakar (UTC+0, sans heure d'été). */
export const dakarHour = (d: Date) => d.getUTCHours();

export function isQuietTime(d: Date): boolean {
  const h = dakarHour(d);
  return h >= 22 || h < 7;
}

export function decidePush(c: PushContext): PushDecision {
  if (!c.hasToken) return "skip";
  if (c.quietHours && isQuietTime(c.now)) return "defer";
  // L'offreur qui préfère un résumé reçoit les nouvelles demandes non urgentes groupées
  if (c.type === "new_request" && !c.instantAlerts && c.priority !== "high") return "defer";
  // Plafond quotidien : au-delà, regroupement (les messages du demandeur passent toujours)
  if (c.sentLast24h >= c.dailyLimit && c.type === "new_request") return "defer";
  return "send";
}

/** Texte d'un résumé groupé de notifications différées. */
export function digestText(items: { type: string; title: string; body: string }[]): { title: string; body: string } {
  if (items.length === 1) return { title: items[0].title, body: items[0].body };
  const newRequests = items.filter((i) => i.type === "new_request").length;
  const others = items.length - newRequests;
  const title = newRequests > 0
    ? `${newRequests} nouvelle${newRequests > 1 ? "s" : ""} demande${newRequests > 1 ? "s" : ""} dans vos zones`
    : `${items.length} nouvelles notifications`;
  const body = newRequests > 0 && others > 0
    ? `Et ${others} autre${others > 1 ? "s" : ""} notification${others > 1 ? "s" : ""}. Ouvrez Dëkk pour voir.`
    : "Ouvrez Dëkk pour voir le détail.";
  return { title, body };
}
