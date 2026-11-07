// Appels à l'API OpenAI : transcription du vocal et extraction structurée.
import { buildExtractionMessages, EXTRACTION_SCHEMA, type Zone } from "./extract.ts";

const API = "https://api.openai.com/v1";

export class OpenAIError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

async function check(res: Response): Promise<any> {
  const text = await res.text();
  if (!res.ok) throw new OpenAIError(`OpenAI ${res.status}: ${text.slice(0, 400)}`, res.status);
  return JSON.parse(text);
}

export async function transcribe(
  audio: Blob, filename: string, prompt: string, apiKey: string,
  model = "gpt-4o-mini-transcribe", fallbackModel = "whisper-1",
): Promise<{ text: string; model: string }> {
  const call = async (m: string) => {
    const form = new FormData();
    form.append("file", audio, filename);
    form.append("model", m);
    form.append("prompt", prompt);
    form.append("response_format", "json");
    const res = await fetch(`${API}/audio/transcriptions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    });
    const json = await check(res);
    return { text: String(json.text ?? "").trim(), model: m };
  };
  try {
    return await call(model);
  } catch (e) {
    // Modèle indisponible ou format refusé : on retente une fois avec Whisper
    if (fallbackModel && fallbackModel !== model && e instanceof OpenAIError && e.status >= 400 && e.status !== 401) {
      return await call(fallbackModel);
    }
    throw e;
  }
}

export async function extract(transcript: string, zones: Zone[], apiKey: string, model = "gpt-4o-mini"): Promise<unknown> {
  const res = await fetch(`${API}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      temperature: 0,
      messages: buildExtractionMessages(transcript, zones),
      response_format: { type: "json_schema", json_schema: EXTRACTION_SCHEMA },
    }),
  });
  const json = await check(res);
  const content = json.choices?.[0]?.message?.content;
  if (!content) throw new OpenAIError("Réponse d'extraction vide", 502);
  return JSON.parse(content);
}
