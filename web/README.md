# boxnumber.co

Сайт — Cloudflare Worker `boxnumber-site` (аккаунт Cloudflare владельца), кастомные домены `boxnumber.co` и `www.boxnumber.co`.
Код — `worker.js`. Переменные: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable-ключ, не секрет), `APP_STORE_URL` (пусто — «скоро в App Store»);
секрет `WAITLIST_SITE_KEY` — совпадает с `app_config.waitlist_site_key` в базе (по нему функция `waitlist` пускает только сайт).

- `/.well-known/apple-app-site-association` — universal links для `/b/*` (Team 2P3PUF975G, co.boxnumber.app).
  В приложении — entitlement `applinks:boxnumber.co`; capability на App ID включается workflow «ASC maintenance» → `associated-domains`.
- `/b/<код>` — страница общего места: RPC `share_preview` (миграция 0012, anon), кнопка `boxno://b/<код>`.
- `/` → 302 на `/<язык>/`. Языки — как в приложении: ru, uk, en, de, fr, es, it, nl, pl, pt.
  Выбор языка: cookie `lang` (ставится только явным выбором в переключателе, `?l=1`) → `Accept-Language` браузера по весу q →
  страна Cloudflare (`request.cf.country`), только если заголовка нет → `en`. Автоопределение только на корне `/`:
  страницы `/<язык>/` всегда показывают свой язык (их индексирует поиск), у каждой — `hreflang` на все языки и `x-default` = `/`.
  `/sitemap.xml` с `hreflang`, `/robots.txt`.
- `/<язык>/` — заглавная с формой «Сообщить о запуске» → `POST /<язык>/notify` → Edge Function `waitlist` (миграция 0017).
  Double opt-in: письмо через Resend со ссылкой `/w/c/<token>`; отписка — `/w/u/<token>`. Обе страницы делают действие
  только по кнопке (POST), чтобы почтовые сканеры не подтверждали и не отписывали сами. Ловушка для ботов — скрытое поле `website`,
  лимит — 5 новых адресов с одного IP в час, повтор письма — не чаще раза в 10 минут.
- `/b/<код>` и служебные страницы — на языке посетителя (cookie → Accept-Language).

Деплой: Cloudflare API (в metadata `keep_bindings: ["plain_text","secret_text"]`, иначе переменные и секрет пропадут) `PUT /accounts/{id}/workers/scripts/boxnumber-site` (multipart: metadata + worker.js) — делается через коннектор Cloudflare в Claude; при изменении кода задеплоить заново.
