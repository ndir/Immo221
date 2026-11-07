// Test de bout en bout de la page web en mode démonstration (Chromium + micro simulé).
// Lancer depuis web/ : python3 -m http.server 8765 & node tests/e2e.mjs
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";

const BASE = process.env.BASE_URL || "http://localhost:8765/?demo=1";
const OUT = process.env.SHOTS || "tests/screenshots";
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({
  args: ["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream", "--autoplay-policy=no-user-gesture-required"],
});
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, permissions: ["microphone"] });
const page = await ctx.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => m.type() === "error" && !/fonts\.g|Failed to load resource/.test(m.text()) && errors.push(m.text()));

const shot = (name) => page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
const step = (msg) => console.log("→", msg);

await page.goto(BASE);
await page.waitForSelector("#s-record:not([hidden])");
await shot("1-accueil");

step("enregistrement 3 s");
await page.click("#mic");
await page.waitForFunction(() => document.querySelector("#recorder").dataset.state === "recording");
await page.waitForTimeout(3200);
await shot("2-enregistrement");
await page.click("#mic");
await page.waitForSelector("#review:not([hidden])");
await shot("3-reecoute");

step("numéro et code");
await page.click("#send");
await page.waitForSelector("#s-phone:not([hidden])");
await page.fill("#name", "Awa");
await page.fill("#phone", "12345");
await page.click("#send-code");
await page.waitForSelector("#toast:not([hidden])");
await page.fill("#phone", "77 123 45 34");
await page.click("#send-code");
await page.waitForSelector("#code-form:not([hidden])");
await page.fill("#code", "000000");
await page.click("#verify");
await page.waitForFunction(() => /Code incorrect/.test(document.querySelector("#toast").textContent));
await page.fill("#code", "123456");
await shot("4-code");
await page.click("#verify");

step("traitement puis fiche");
await page.waitForSelector("#s-processing:not([hidden])");
await shot("5-traitement");
await page.waitForSelector("#s-fiche:not([hidden])", { timeout: 10000 });
const zones = await page.$$eval("#zone-chips .zone-chip", (els) => els.map((e) => e.firstChild.textContent));
if (zones.join() !== "Mermoz,Sacré-Cœur") throw new Error("zones inattendues : " + zones);
if ((await page.inputValue("#budget_max")) !== "300 000") throw new Error("budget mal affiché");
await shot("6-fiche");

step("validation : consentement obligatoire");
await page.click("#publish");
await page.waitForSelector("#fiche-error:not([hidden])");

step("ajout d'une zone, publication");
await page.fill("#zone-search", "Point E");
await page.dispatchEvent("#zone-search", "change");
const zones2 = await page.$$eval("#zone-chips .zone-chip", (els) => els.length);
if (zones2 !== 3) throw new Error("zone non ajoutée");
await page.check("#consent");
await page.click("#publish");
await page.waitForSelector("#s-done:not([hidden])");
const doneText = await page.textContent("#done-text");
if (!doneText.includes("+221 77 ••• •• 34")) throw new Error("numéro masqué absent : " + doneText);
await shot("7-publiee");

step("suivi");
await page.click("text=Non merci, WhatsApp me suffit");
await page.waitForSelector("#s-suivi:not([hidden])");
await page.waitForSelector(".req");
await page.waitForTimeout(1700);
await page.evaluate(() => (location.hash = ""));
await page.evaluate(() => (location.hash = "#suivi"));
await page.waitForSelector(".owner-line");
await shot("8-suivi");

step("clôture avec avis");
await page.click("text=J'ai trouvé");
await page.waitForSelector("#close-dialog[open]");
await shot("9-cloture");
await page.click("#close-confirm");
await page.waitForFunction(() => document.querySelector(".req-status")?.textContent === "Trouvé");
await shot("10-trouve");

await browser.close();
if (errors.length) {
  console.error("Erreurs JS :", errors);
  process.exit(1);
}
console.log("E2E OK");
