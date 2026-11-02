// Page web Dëkk : dépôt d'une demande vocale sans application, puis suivi.
import { createBackend, friendlyError } from "./backend.js";

const cfg = window.DEKK_CONFIG;
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => [...document.querySelectorAll(sel)];

const MAX_SECONDS = 90;
const state = {
  backend: null,
  zones: [],
  audio: null,          // { blob, mime, url, duration }
  phone: null,
  request: null,        // demande en cours de vérification
  chosenZones: [],      // [{id, name, city}]
  closing: null,        // demande en cours de clôture
};

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------
function show(name) {
  for (const s of $$(".screen")) s.hidden = s.id !== `s-${name}`;
  $("#toast").hidden = true;
  window.scrollTo(0, 0);
  const h1 = $(`#s-${name} h1`);
  if (h1) { h1.tabIndex = -1; h1.focus({ preventScroll: true }); }
}

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), 4000);
}

const fcfa = (n) => (n == null ? "" : Number(n).toLocaleString("fr-FR").replace(/ | /g, " "));
const parseAmount = (s) => {
  const digits = String(s || "").replace(/[^\d]/g, "");
  return digits ? Number(digits) : null;
};

// ---------------------------------------------------------------------------
// 1. Enregistrement
// ---------------------------------------------------------------------------
const rec = { stream: null, recorder: null, chunks: [], start: 0, timer: null, raf: null, ctx: null };

function pickMime() {
  const options = ["audio/webm;codecs=opus", "audio/mp4", "audio/webm", "audio/ogg;codecs=opus"];
  return options.find((m) => window.MediaRecorder && MediaRecorder.isTypeSupported(m)) || "";
}

function setRecorderState(s) {
  $("#recorder").dataset.state = s;
  $("#review").hidden = s !== "review";
  const mic = $("#mic");
  mic.setAttribute("aria-label", s === "recording" ? "Arrêter l'enregistrement" : "Appuyez pour enregistrer votre vocal");
}

function buildBars() {
  const bars = $("#bars");
  bars.innerHTML = "";
  for (let i = 0; i < 28; i++) bars.appendChild(document.createElement("span"));
}

async function startRecording() {
  if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
    toast("Votre navigateur ne permet pas d'enregistrer. Essayez Chrome ou téléchargez l'application.");
    return;
  }
  try {
    rec.stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
  } catch {
    toast("Accès au micro refusé. Autorisez le micro dans votre navigateur puis réessayez.");
    return;
  }
  const mime = pickMime();
  rec.recorder = new MediaRecorder(rec.stream, mime ? { mimeType: mime, audioBitsPerSecond: 32000 } : undefined);
  rec.chunks = [];
  rec.recorder.ondataavailable = (e) => e.data.size && rec.chunks.push(e.data);
  rec.recorder.onstop = onRecordingStopped;
  rec.recorder.start(250);
  rec.start = performance.now();
  setRecorderState("recording");
  tick();
  rec.timer = setInterval(tick, 250);
  animateBars();
}

function tick() {
  const s = Math.floor((performance.now() - rec.start) / 1000);
  const mm = Math.floor(s / 60), ss = String(s % 60).padStart(2, "0");
  $("#rec-status").textContent = `Enregistrement · ${mm}:${ss} / 1:30`;
  if (s >= MAX_SECONDS) stopRecording();
}

function animateBars() {
  try {
    rec.ctx = new (window.AudioContext || window.webkitAudioContext)();
    const analyser = rec.ctx.createAnalyser();
    analyser.fftSize = 64;
    rec.ctx.createMediaStreamSource(rec.stream).connect(analyser);
    const data = new Uint8Array(analyser.frequencyBinCount);
    const bars = $$("#bars span");
    const draw = () => {
      analyser.getByteFrequencyData(data);
      bars.forEach((b, i) => (b.style.height = `${6 + (data[i % data.length] / 255) * 42}px`));
      rec.raf = requestAnimationFrame(draw);
    };
    draw();
  } catch { /* visualisation facultative */ }
}

function stopRecording() {
  clearInterval(rec.timer);
  cancelAnimationFrame(rec.raf);
  if (rec.recorder?.state === "recording") rec.recorder.stop();
  rec.stream?.getTracks().forEach((t) => t.stop());
  rec.ctx?.close().catch(() => {});
}

function onRecordingStopped() {
  const duration = (performance.now() - rec.start) / 1000;
  const mime = (rec.recorder.mimeType || "audio/webm").split(";")[0];
  const blob = new Blob(rec.chunks, { type: mime });
  if (duration < 2 || blob.size < 1000) {
    setRecorderState("idle");
    $("#rec-status").textContent = "Vocal trop court. Appuyez et parlez quelques secondes.";
    return;
  }
  if (state.audio?.url) URL.revokeObjectURL(state.audio.url);
  state.audio = { blob, mime, url: URL.createObjectURL(blob), duration };
  $("#preview").src = state.audio.url;
  const s = Math.round(duration);
  $("#rec-status").textContent = `Votre vocal · ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  setRecorderState("review");
}

$("#mic").addEventListener("click", () => {
  const s = $("#recorder").dataset.state;
  if (s === "recording") stopRecording();
  else startRecording();
});
$("#restart").addEventListener("click", () => {
  setRecorderState("idle");
  $("#rec-status").textContent = "Appuyez pour parler · 1 min 30 max";
});
$("#send").addEventListener("click", async () => {
  if (!state.audio) return;
  const session = await state.backend.session();
  if (session) processAudio();
  else {
    $("#s-phone .step").textContent = "Étape 2 sur 3";
    $("#s-phone h1").textContent = "Votre numéro WhatsApp";
    show("phone");
  }
});

// ---------------------------------------------------------------------------
// 2. Numéro + code SMS
// ---------------------------------------------------------------------------
function normalizePhone(raw) {
  let d = String(raw).replace(/\D/g, "");
  if (d.startsWith("00221")) d = d.slice(5);
  else if (d.startsWith("221") && d.length === 12) d = d.slice(3);
  return /^7[05678]\d{7}$/.test(d) ? `+221${d}` : null;
}

$("#phone-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const phone = normalizePhone($("#phone").value);
  if (!phone) { toast("Entrez un numéro sénégalais à 9 chiffres, par exemple 77 123 45 67."); return; }
  const btn = $("#send-code");
  btn.disabled = true;
  try {
    await state.backend.sendCode(phone);
    state.phone = phone;
    $("#phone-form").hidden = true;
    $("#code-form").hidden = false;
    $("#code").focus();
  } catch (err) {
    toast(friendlyError(err));
  } finally {
    btn.disabled = false;
  }
});

$("#code-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const code = $("#code").value.replace(/\D/g, "");
  if (code.length < 6) { toast("Le code comporte 6 chiffres."); return; }
  const btn = $("#verify");
  btn.disabled = true;
  try {
    await state.backend.verifyCode(state.phone, code, $("#name").value.trim());
    if (state.audio) processAudio();
    else openSuivi();
  } catch (err) {
    toast(friendlyError(err));
  } finally {
    btn.disabled = false;
  }
});

$("#change-phone").addEventListener("click", () => {
  $("#code-form").hidden = true;
  $("#phone-form").hidden = false;
});

// ---------------------------------------------------------------------------
// 3. Traitement IA
// ---------------------------------------------------------------------------
async function processAudio(retryId) {
  show("processing");
  $("#process-error").hidden = true;
  $(".spinner").hidden = false;
  try {
    const result = retryId
      ? await state.backend.process(retryId)
      : await state.backend.uploadAndProcess(state.audio.blob, state.audio.mime, state.audio.duration);
    state.request = result.request;
    openFiche();
  } catch (err) {
    $(".spinner").hidden = true;
    $("#process-error").hidden = false;
    $("#process-error-text").textContent = err.userMessage || friendlyError(err);
    $("#retry-process").onclick = () => processAudio(state.request?.id || null);
  }
}

// ---------------------------------------------------------------------------
// 4. Fiche
// ---------------------------------------------------------------------------
function renderZoneChips() {
  const box = $("#zone-chips");
  box.innerHTML = "";
  for (const z of state.chosenZones) {
    const chip = document.createElement("span");
    chip.className = "zone-chip";
    chip.textContent = z.name;
    const del = document.createElement("button");
    del.type = "button";
    del.setAttribute("aria-label", `Retirer ${z.name}`);
    del.textContent = "×";
    del.onclick = () => {
      state.chosenZones = state.chosenZones.filter((x) => x.id !== z.id);
      renderZoneChips();
    };
    chip.appendChild(del);
    box.appendChild(chip);
  }
}

function zoneLabel(z) { return z.name === z.city ? z.name : `${z.name} (${z.city})`; }

function fillZoneList() {
  $("#zone-list").innerHTML = state.zones.map((z) => `<option value="${zoneLabel(z).replace(/"/g, "&quot;")}"></option>`).join("");
}

$("#zone-search").addEventListener("change", (e) => {
  const v = e.target.value.trim().toLowerCase();
  const z = state.zones.find((x) => zoneLabel(x).toLowerCase() === v || x.name.toLowerCase() === v);
  if (z && !state.chosenZones.some((x) => x.id === z.id)) {
    state.chosenZones.push(z);
    renderZoneChips();
    $("#zone-free").hidden = true;
  } else if (!z && v) {
    toast("Lieu inconnu : choisissez-le dans la liste proposée.");
  }
  e.target.value = "";
});

function openFiche() {
  const r = state.request;
  $("#transcript").textContent = r.transcript ? `« ${r.transcript} »` : "";
  $("#fiche-audio").src = state.audio?.url || "";
  $("#fiche-audio").hidden = !state.audio;
  for (const input of $$('input[name="transaction"]')) input.checked = input.value === r.transaction;
  $("#property").value = r.property || "";
  state.chosenZones = (r.zone_ids || []).map((id) => state.zones.find((z) => z.id === id)).filter(Boolean);
  renderZoneChips();
  $("#zone-free").hidden = !r.zone_free_text;
  $("#zone-free").textContent = r.zone_free_text ? `Lieu non reconnu : « ${r.zone_free_text} ». Ajoutez-le depuis la liste si possible.` : "";
  $("#budget_max").value = fcfa(r.budget_max);
  $("#budget_period").value = r.budget_period || (["achat", "terrain"].includes(r.transaction) ? "total" : "mois");
  $("#bedrooms_min").value = r.bedrooms_min ?? "";
  $("#move_in").value = r.move_in || "";
  $("#is_urgent").checked = Boolean(r.is_urgent);
  $("#summary").value = r.summary || "";
  $("#consent").checked = false;
  $("#fiche-error").hidden = true;
  state.initialFiche = JSON.stringify(readFiche());
  show("fiche");
}

function readFiche() {
  const tx = $$('input[name="transaction"]').find((i) => i.checked)?.value || null;
  return {
    transaction: tx,
    property: $("#property").value || null,
    zone_ids: state.chosenZones.map((z) => z.id),
    zone_free_text: state.chosenZones.length ? null : (state.request.zone_free_text || null),
    budget_min: state.request.budget_min ?? null,
    budget_max: parseAmount($("#budget_max").value),
    budget_period: $("#budget_period").value,
    bedrooms_min: $("#bedrooms_min").value === "" ? null : Number($("#bedrooms_min").value),
    furnished: state.request.furnished ?? null,
    move_in: $("#move_in").value.trim() || null,
    is_urgent: $("#is_urgent").checked,
    summary: $("#summary").value.trim() || null,
    visibility_days: Number($$('input[name="visibility"]').find((i) => i.checked)?.value || 15),
  };
}

$("#budget_max").addEventListener("blur", (e) => { e.target.value = fcfa(parseAmount(e.target.value)); });

$("#fiche-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const f = readFiche();
  const err = $("#fiche-error");
  const fail = (msg) => { err.textContent = msg; err.hidden = false; err.scrollIntoView({ block: "center" }); };
  if (!f.transaction) return fail("Choisissez : location, colocation, achat ou terrain.");
  if (!f.zone_ids.length && !f.zone_free_text) return fail("Ajoutez au moins un quartier ou une ville.");
  if (!$("#consent").checked) return fail("Cochez la case d'accord pour être contacté sur WhatsApp.");
  err.hidden = true;
  const { visibility_days, ...rest } = f;
  f.user_edited = JSON.stringify({ ...rest, visibility_days: 15 }) !== JSON.stringify({ ...JSON.parse(state.initialFiche), visibility_days: 15 });

  const btn = $("#publish");
  btn.disabled = true;
  try {
    const published = await state.backend.publish(state.request.id, f);
    const zones = state.chosenZones.map((z) => z.name);
    $("#done-text").textContent =
      `Les offreurs de ${zones.length ? zones.join(", ") : "votre zone"} vont vous écrire sur WhatsApp` +
      (state.phone ? ` au ${state.phone.replace(/^\+221(\d{2})\d{5}(\d{2})$/, "+221 $1 ••• •• $2")}.` : ".");
    state.request = published;
    state.audio = null;
    show("done");
  } catch (er) {
    fail(friendlyError(er));
  } finally {
    btn.disabled = false;
  }
});

// ---------------------------------------------------------------------------
// 5. Suivi
// ---------------------------------------------------------------------------
const STATUS = {
  published: "En ligne", draft: "À vérifier", failed: "Traitement échoué",
  found: "Trouvé", removed: "Retirée", expired: "Expirée",
};

async function openSuivi() {
  const session = await state.backend.session();
  if (!session) {
    state.audio = null;
    $("#code-form").hidden = true;
    $("#phone-form").hidden = false;
    show("phone");
    $("#s-phone .step").textContent = "Connexion";
    $("#s-phone h1").textContent = "Retrouvez votre demande";
    return;
  }
  show("suivi");
  const box = $("#requests");
  box.innerHTML = '<p class="muted">Chargement…</p>';
  try {
    const list = await state.backend.myRequests();
    box.innerHTML = "";
    if (!list.length) box.innerHTML = '<p class="muted">Aucune demande pour le moment.</p>';
    for (const r of list) box.appendChild(renderRequest(r));
  } catch (err) {
    box.innerHTML = "";
    toast(friendlyError(err));
  }
}

function renderRequest(r) {
  const el = document.createElement("article");
  el.className = "req";
  const expires = r.expires_at ? new Date(r.expires_at) : null;
  const daysLeft = expires ? Math.ceil((expires - Date.now()) / 86400000) : null;
  el.innerHTML = `
    <div class="row-between">
      <span class="req-status ${r.status}"></span>
      <span class="muted small"></span>
    </div>
    <p class="req-title"></p>
    <div class="req-stats">
      <span><strong>${r.listen_count ?? 0}</strong> écoutes</span>
      <span><strong>${r.contacts_count ?? 0} / ${r.max_contacts ?? 5}</strong> contacts</span>
    </div>
    <div class="contacts"></div>
    <div class="req-actions"></div>`;
  el.querySelector(".req-status").textContent = STATUS[r.status] || r.status;
  el.querySelector(".muted.small").textContent =
    r.status === "published" && daysLeft != null ? (daysLeft <= 1 ? "expire demain" : `encore ${daysLeft} jours`) : "";
  el.querySelector(".req-title").textContent = r.summary || "Demande";

  const actions = el.querySelector(".req-actions");
  const add = (label, cls, fn) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = `btn btn-sm ${cls}`;
    b.textContent = label;
    b.onclick = fn;
    actions.appendChild(b);
  };
  if (r.status === "published" || r.status === "expired") {
    add("Prolonger de 15 jours", "btn-outline", async () => {
      try { await state.backend.extend(r.id, 15); toast("Demande prolongée."); openSuivi(); } catch (e) { toast(friendlyError(e)); }
    });
  }
  if (r.status === "published") {
    add("J'ai trouvé", "btn-primary", () => openClose(r));
    add("Retirer", "btn-ghost", async () => {
      if (!confirm("Retirer cette demande ? Les offreurs ne la verront plus.")) return;
      try { await state.backend.remove(r.id); openSuivi(); } catch (e) { toast(friendlyError(e)); }
    });
  }
  if (r.contacts_count > 0) loadContacts(r.id, el.querySelector(".contacts"));
  return el;
}

const ROLE = { agency: "Agence", broker: "Démarcheur", owner: "Propriétaire", admin: "Équipe Dëkk" };

async function loadContacts(requestId, box) {
  try {
    const list = await state.backend.contacts(requestId);
    for (const c of list) {
      const line = document.createElement("div");
      line.className = "owner-line";
      const left = document.createElement("span");
      left.textContent = `${c.owner_name || "Offreur"} · ${ROLE[c.owner_role] || ""}${c.is_verified ? " vérifié(e)" : ""}`;
      const right = document.createElement("span");
      right.className = "muted";
      right.textContent = c.rating_count ? `${String(c.rating_avg).replace(".", ",")} ★` : "Nouveau";
      line.append(left, right);
      box.appendChild(line);
    }
  } catch { /* liste facultative */ }
}

async function openClose(r) {
  state.closing = r;
  const box = $("#close-owners");
  box.innerHTML = "";
  let contacts = [];
  try { contacts = await state.backend.contacts(r.id); } catch { /* ignore */ }
  const options = [...contacts.map((c) => ({ id: c.owner_id, label: c.owner_name || "Offreur" })), { id: "", label: "Personne de Dëkk" }];
  options.forEach((o, i) => {
    const l = document.createElement("label");
    l.className = "check";
    const input = document.createElement("input");
    input.type = "radio";
    input.name = "helped";
    input.value = o.id;
    input.checked = i === 0;
    const span = document.createElement("span");
    span.textContent = o.label;
    l.append(input, span);
    box.appendChild(l);
  });
  $("#stars").closest("fieldset").hidden = contacts.length === 0;
  paintStars();
  $("#close-dialog").showModal();
}

function paintStars() {
  const v = Number($$('input[name="rating"]').find((i) => i.checked)?.value || 0);
  $$("#stars span").forEach((s, i) => s.classList.toggle("on", i < v));
}
$("#stars").addEventListener("change", paintStars);

$("#close-dialog").addEventListener("close", async () => {
  if ($("#close-dialog").returnValue !== "ok" || !state.closing) return;
  const helped = $$('input[name="helped"]').find((i) => i.checked)?.value || null;
  const rating = helped ? Number($$('input[name="rating"]').find((i) => i.checked)?.value || 0) : null;
  try {
    await state.backend.close(state.closing.id, helped, rating);
    toast("Félicitations pour votre nouveau logement !");
    openSuivi();
  } catch (e) {
    toast(friendlyError(e));
  }
});

$("#sign-out").addEventListener("click", async () => {
  await state.backend.signOut();
  location.hash = "";
  show("record");
});

// ---------------------------------------------------------------------------
// Démarrage
// ---------------------------------------------------------------------------
for (const b of $$("[data-go]")) {
  b.addEventListener("click", (e) => {
    e.preventDefault();
    if (b.dataset.go === "record") { history.replaceState(null, "", location.pathname + location.search); show("record"); }
  });
}
window.addEventListener("hashchange", () => { if (location.hash === "#suivi") openSuivi(); });

async function init() {
  buildBars();
  state.backend = await createBackend(cfg);
  $("#demo-badge").hidden = !state.backend.demo;
  $("#demo-code-hint").hidden = !state.backend.demo;
  $("#suivi-link").textContent = `${cfg.siteUrl.replace(/^https?:\/\//, "")}/#suivi`;
  $("#suivi-link").href = "#suivi";

  const play = cfg.playStoreUrl;
  for (const a of $$("[data-play-link]")) {
    if (play) a.href = play;
    else a.addEventListener("click", (e) => { e.preventDefault(); toast("L'application arrive bientôt sur Google Play."); });
  }
  $("#app-banner-1").hidden = false;

  try {
    state.zones = await state.backend.zones();
    fillZoneList();
    const settings = await state.backend.appSettings();
    $("#free-pill").hidden = !settings.free_mode;
  } catch (err) {
    toast(friendlyError(err));
  }

  if (location.hash === "#suivi") openSuivi();
  else show("record");
}

init();
