// Подписка «Сообщить о запуске» с сайта boxnumber.co. Вызывает только Cloudflare Worker сайта
// (заголовок x-site-key = секрет WAITLIST_SITE_KEY), поэтому verify_jwt выключен.
//
// POST { action: "join", email, locale, country?, ip? }  → строка waitlist + письмо со ссылкой подтверждения
// POST { action: "confirm", token }                      → confirmed_at
// POST { action: "unsubscribe", token }                  → unsubscribed_at
// Ответ всегда { ok, locale? } — по ответу нельзя узнать, есть ли адрес в списке.
// Секрет RESEND_API_KEY — в окружении функций. Ключ сайта и соль — в таблице app_config (только сервисный ключ),
// чтобы не заводить секреты вручную в панели: waitlist_site_key (тот же — секрет Worker WAITLIST_SITE_KEY), waitlist_salt.
import { createClient } from "npm:@supabase/supabase-js@2";

const LANGS = ["ru", "uk", "en", "de", "fr", "es", "it", "nl", "pl", "pt"] as const;
type Lang = typeof LANGS[number];
const FROM = Deno.env.get("WAITLIST_FROM") ?? "Box Nº <noreply@mail.boxnumber.co>";
const SITE = "https://boxnumber.co";

const MAIL: Record<Lang, { subj: string; p1: string; btn: string; ignore: string; unsub: string }> = {
  ru: { subj: "Подтвердите подписку на Box Nº", p1: "Вы оставили этот адрес на boxnumber.co, чтобы узнать о запуске приложения Box Nº. Подтвердите его — и мы напишем, когда приложение выйдет.", btn: "Подтвердить", ignore: "Если это были не вы, просто не отвечайте на письмо — подписки не будет.", unsub: "Отписаться" },
  uk: { subj: "Підтвердьте підписку на Box Nº", p1: "Ви залишили цю адресу на boxnumber.co, щоб дізнатися про запуск застосунку Box Nº. Підтвердьте її — і ми напишемо, коли застосунок вийде.", btn: "Підтвердити", ignore: "Якщо це були не ви, просто не відповідайте на лист — підписки не буде.", unsub: "Відписатися" },
  en: { subj: "Confirm your Box Nº signup", p1: "You left this address on boxnumber.co to hear when the Box Nº app launches. Confirm it and we'll email you when it's out.", btn: "Confirm", ignore: "If this wasn't you, just ignore this email — you won't be subscribed.", unsub: "Unsubscribe" },
  de: { subj: "Bitte bestätige deine Anmeldung bei Box Nº", p1: "Du hast diese Adresse auf boxnumber.co hinterlassen, um vom Start der App Box Nº zu erfahren. Bestätige sie, dann schreiben wir dir, sobald die App da ist.", btn: "Bestätigen", ignore: "Warst du das nicht? Dann ignoriere diese E-Mail einfach – du wirst nicht angemeldet.", unsub: "Abmelden" },
  fr: { subj: "Confirmez votre inscription à Box Nº", p1: "Vous avez laissé cette adresse sur boxnumber.co pour être prévenu du lancement de l'application Box Nº. Confirmez-la et nous vous écrirons dès sa sortie.", btn: "Confirmer", ignore: "Si ce n'était pas vous, ignorez simplement cet e-mail : vous ne serez pas inscrit.", unsub: "Se désinscrire" },
  es: { subj: "Confirma tu suscripción a Box Nº", p1: "Dejaste esta dirección en boxnumber.co para saber cuándo se lanza la app Box Nº. Confírmala y te escribiremos cuando esté disponible.", btn: "Confirmar", ignore: "Si no fuiste tú, ignora este correo: no quedarás suscrito.", unsub: "Darse de baja" },
  it: { subj: "Conferma la tua iscrizione a Box Nº", p1: "Hai lasciato questo indirizzo su boxnumber.co per sapere quando uscirà l'app Box Nº. Confermalo e ti scriveremo al lancio.", btn: "Conferma", ignore: "Se non sei stato tu, ignora questa e-mail: non verrai iscritto.", unsub: "Annulla iscrizione" },
  nl: { subj: "Bevestig je aanmelding bij Box Nº", p1: "Je hebt dit adres achtergelaten op boxnumber.co om te horen wanneer de app Box Nº verschijnt. Bevestig het en we mailen je zodra de app er is.", btn: "Bevestigen", ignore: "Was jij dit niet? Negeer deze e-mail dan gewoon – je wordt niet aangemeld.", unsub: "Afmelden" },
  pl: { subj: "Potwierdź zapis do Box Nº", p1: "Zostawiłeś ten adres na boxnumber.co, aby dowiedzieć się o premierze aplikacji Box Nº. Potwierdź go, a napiszemy, gdy aplikacja będzie dostępna.", btn: "Potwierdź", ignore: "Jeśli to nie Ty, po prostu zignoruj tę wiadomość — nie zostaniesz zapisany.", unsub: "Wypisz się" },
  pt: { subj: "Confirme a sua inscrição no Box Nº", p1: "Deixou este endereço em boxnumber.co para saber quando a app Box Nº for lançada. Confirme-o e escreveremos assim que estiver disponível.", btn: "Confirmar", ignore: "Se não foi você, ignore este e-mail — não ficará inscrito.", unsub: "Cancelar inscrição" },
};

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json" } });

const isLang = (s: unknown): s is Lang => typeof s === "string" && (LANGS as readonly string[]).includes(s);
const isUuid = (s: unknown): s is string => typeof s === "string" && /^[0-9a-f-]{36}$/i.test(s);
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

let cfgCache: Record<string, string> | null = null;
// deno-lint-ignore no-explicit-any
async function config(db: any) {
  if (cfgCache) return cfgCache;
  const { data } = await db.from("app_config").select("key, value").in("key", ["waitlist_site_key", "waitlist_salt"]);
  cfgCache = Object.fromEntries((data ?? []).map((r: { key: string; value: string }) => [r.key, r.value]));
  return cfgCache;
}

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sendConfirm(email: string, lang: Lang, token: string) {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) throw new Error("RESEND_API_KEY missing");
  const t = MAIL[lang];
  const confirm = `${SITE}/w/c/${token}`;
  const unsub = `${SITE}/w/u/${token}`;
  const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:520px;color:#16171A">
<p style="font-size:26px;font-weight:900;margin:0 0 20px">Box <span style="color:#F0561D">Nº</span></p>
<p style="font-size:16px;line-height:1.5">${esc(t.p1)}</p>
<p style="margin:24px 0"><a href="${confirm}" style="display:inline-block;background:#16171A;color:#fff;text-decoration:none;font-weight:700;border-radius:24px;padding:14px 28px">${esc(t.btn)}</a></p>
<p style="font-size:14px;line-height:1.5;color:#5E6066">${esc(t.ignore)}</p>
<p style="font-size:12px;color:#5E6066"><a href="${unsub}" style="color:#5E6066">${esc(t.unsub)}</a></p></div>`;
  const text = `${t.p1}\n\n${t.btn}: ${confirm}\n\n${t.ignore}\n\n${t.unsub}: ${unsub}`;
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: FROM, to: [email], subject: t.subj, html, text,
      headers: { "List-Unsubscribe": `<${unsub}>` },
    }),
  });
  if (!res.ok) throw new Error(`resend ${res.status}: ${await res.text()}`);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const cfg = await config(db);
  if (!cfg.waitlist_site_key || req.headers.get("x-site-key") !== cfg.waitlist_site_key) return json({ error: "forbidden" }, 403);

  const b = await req.json().catch(() => ({}));

  if (b.action === "confirm" || b.action === "unsubscribe") {
    if (!isUuid(b.token)) return json({ ok: false });
    const { data: row } = await db.from("waitlist").select("id, locale, confirmed_at").eq("token", b.token).maybeSingle();
    if (!row) return json({ ok: false });
    const patch = b.action === "confirm"
      ? { confirmed_at: row.confirmed_at ?? new Date().toISOString(), unsubscribed_at: null }
      : { unsubscribed_at: new Date().toISOString() };
    await db.from("waitlist").update(patch).eq("id", row.id);
    return json({ ok: true, locale: row.locale });
  }

  if (b.action !== "join") return json({ error: "action" }, 400);
  const email = String(b.email ?? "").trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return json({ ok: false, error: "email" }, 400);
  const lang: Lang = isLang(b.locale) ? b.locale : "en";
  const country = typeof b.country === "string" ? b.country.slice(0, 2) : null;
  const ipHash = b.ip ? await sha256((cfg.waitlist_salt ?? "") + String(b.ip)) : null;

  // Не больше 5 новых адресов с одного IP в час — дальше молча «ok», без писем.
  if (ipHash) {
    const since = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await db.from("waitlist").select("id", { count: "exact", head: true })
      .eq("ip_hash", ipHash).gte("created_at", since);
    if ((count ?? 0) >= 5) return json({ ok: true });
  }

  const { data: existing } = await db.from("waitlist")
    .select("id, token, confirmed_at, unsubscribed_at, confirm_sent_at").eq("email", email).maybeSingle();

  let token: string;
  if (!existing) {
    const { data, error } = await db.from("waitlist")
      .insert({ email, locale: lang, country, source: "site", ip_hash: ipHash })
      .select("id, token").single();
    if (error || !data) { console.error("insert:", error); return json({ ok: false, error: "save" }, 500); }
    token = data.token;
  } else {
    if (existing.confirmed_at && !existing.unsubscribed_at) return json({ ok: true }); // уже в списке
    // Повторно шлём письмо не чаще раза в 10 минут.
    if (existing.confirm_sent_at && Date.now() - Date.parse(existing.confirm_sent_at) < 600_000) return json({ ok: true });
    token = existing.token;
    await db.from("waitlist").update({ locale: lang, unsubscribed_at: null, confirmed_at: null }).eq("id", existing.id);
  }

  try {
    await sendConfirm(email, lang, token);
    await db.from("waitlist").update({ confirm_sent_at: new Date().toISOString() }).eq("token", token);
  } catch (e) {
    console.error("send:", e);
    return json({ ok: false, error: "send" }, 502);
  }
  return json({ ok: true });
});
