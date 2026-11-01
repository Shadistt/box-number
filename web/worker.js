// Сайт boxnumber.co на Cloudflare Worker (кастомные домены boxnumber.co и www).
// 1) /.well-known/apple-app-site-association — universal links: boxnumber.co/b/<код> открывает приложение.
// 2) /b/<код> — страница для тех, у кого приложения нет: что за место и от кого (RPC share_preview, анонимно),
//    кнопка «Открыть в Box Nº» (boxno://) и ссылка на установку.
// 3) / — заглавная.
// Переменные Worker: SUPABASE_URL, SUPABASE_ANON_KEY, APP_STORE_URL (пусто — «скоро в App Store»).
// Деплой: см. web/README.md.

const TEAM_ID = "2P3PUF975G";
const BUNDLE = "co.boxnumber.app";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname.startsWith("www.")) {
      return Response.redirect(`https://boxnumber.co${url.pathname}${url.search}`, 301);
    }
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/.well-known/apple-app-site-association" || path === "/apple-app-site-association") {
      const aasa = { applinks: { apps: [], details: [{ appIDs: [`${TEAM_ID}.${BUNDLE}`], components: [{ "/": "/b/*", comment: "Общее место по ссылке" }] }] } };
      return new Response(JSON.stringify(aasa), { headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" } });
    }

    const m = path.match(/^\/b\/([A-Za-z0-9_-]{6,32})$/);
    if (m) return sharePage(m[1], env);

    if (path === "/") return html(landing(), 200);
    return html(page("Страница не найдена", `<p class="muted">Такой страницы нет.</p><p><a class="btn" href="/">На главную</a></p>`), 404);
  },
};

async function sharePage(code, env) {
  let p = null;
  try {
    const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/share_preview`, {
      method: "POST",
      headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ p_code: code }),
    });
    if (r.ok) { const rows = await r.json(); p = rows[0] ?? null; }
  } catch (_) { /* покажем страницу без предпросмотра */ }

  const open = `boxno://b/${code}`;
  const install = env.APP_STORE_URL
    ? `<a class="btn ghost" href="${esc(env.APP_STORE_URL)}">Установить Box Nº</a>`
    : `<p class="muted small">Приложение скоро появится в App Store.</p>`;

  if (!p) {
    return html(page("Ссылка не работает", `
      <p class="muted">Ссылка выключена или неверна. Попросите того, кто делился местом, прислать новую.</p>
      <p><a class="btn" href="/">На главную</a></p>`), 404);
  }
  const kind = { box: "Коробка", folder: "Папка", container: "Контейнер", suitcase: "Чемодан или сумка", bag: "Мешок или пакет", wardrobe: "Кофр для одежды", large: "Крупный предмет", custom: "Место" }[p.kind] ?? "Место";
  const title = p.title && p.title.trim() ? esc(p.title) : "Без названия";
  const items = plural(p.items, "вещь", "вещи", "вещей");
  return html(page("Вам открыли место", `
    <p class="muted"><b>${esc(p.owner_name)}</b> делится с вами местом из переезда в Box Nº.</p>
    <div class="card">
      <div class="num">${esc(p.number)}</div>
      <div>
        <div class="t">${title}</div>
        <div class="muted small">${kind} · ${items}${p.password ? " · нужен пароль" : ""}</div>
      </div>
    </div>
    <a class="btn" href="${open}">Открыть в Box Nº</a>
    ${install}
    <p class="muted small">Если приложение установлено, эта ссылка открывается в нём сама. Внутри вы увидите фото всего, что лежит в этом месте.</p>`), 200);
}

function landing() {
  return page("Коробки с номером и фото всего, что внутри", `
    <p class="muted">Box Nº — приложение для переезда: пишете номер маркером на коробке, снимаете вещи, а потом находите любую вещь поиском — в какой она коробке и где коробка.</p>
    <p class="muted small">Скоро в App Store.</p>`, true);
}

function page(h1, body, home = false) {
  return `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(h1)} · Box Nº</title>
<style>
:root{--bg:#F1F0EC;--ink:#16171A;--muted:#5E6066;--accent:#F0561D;--card:#fff;--line:#D9D6CF}
@media(prefers-color-scheme:dark){:root{--bg:#121214;--ink:#F2F1EE;--muted:#9EA0A7;--card:#1E1F23;--line:#33343A}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:-apple-system,"SF Pro Text",Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:440px;margin:0 auto;padding:48px 20px 40px}
.logo{font-size:28px;font-weight:900;margin:0 0 28px}.logo span{color:var(--accent)}
h1{font-size:26px;font-weight:900;line-height:1.15;margin:0 0 12px}
p{font-size:16px;line-height:1.45;margin:0 0 14px}.muted{color:var(--muted)}.small{font-size:14px}
.card{display:flex;gap:14px;align-items:center;background:var(--ink);color:#fff;border-radius:18px;padding:16px;margin:18px 0 20px}
@media(prefers-color-scheme:dark){.card{background:#1E1F23}}
.num{min-width:56px;height:56px;border-radius:14px;background:var(--accent);display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:900;color:#fff;padding:0 10px}
.t{font-size:18px;font-weight:800;margin-bottom:2px}.card .muted{color:#B8B9BE}
.btn{display:block;text-align:center;background:var(--ink);color:#fff;text-decoration:none;font-weight:700;font-size:17px;border-radius:28px;padding:16px;margin:0 0 12px}
@media(prefers-color-scheme:dark){.btn{background:#F2F1EE;color:#16171A}}
.btn.ghost{background:var(--card);color:var(--ink);border:1px solid var(--line)}
</style></head><body><main>
<p class="logo">Box <span>Nº</span></p>
<h1>${esc(h1)}</h1>
${body}
</main></body></html>`;
}

function html(s, status) { return new Response(s, { status, headers: { "content-type": "text/html; charset=utf-8" } }); }
function esc(s) { return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function plural(n, one, few, many) {
  const a = Math.abs(n) % 100, b = a % 10;
  const w = a > 10 && a < 20 ? many : b > 1 && b < 5 ? few : b === 1 ? one : many;
  return `${n} ${w}`;
}
