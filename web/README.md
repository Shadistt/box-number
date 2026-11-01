# boxnumber.co

Сайт — Cloudflare Worker `boxnumber-site` (аккаунт Cloudflare владельца), кастомные домены `boxnumber.co` и `www.boxnumber.co`.
Код — `worker.js`. Переменные: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable-ключ, не секрет), `APP_STORE_URL` (пусто — «скоро в App Store»).

- `/.well-known/apple-app-site-association` — universal links для `/b/*` (Team 2P3PUF975G, co.boxnumber.app).
  В приложении — entitlement `applinks:boxnumber.co`; capability на App ID включается workflow «ASC maintenance» → `associated-domains`.
- `/b/<код>` — страница общего места: RPC `share_preview` (миграция 0012, anon), кнопка `boxno://b/<код>`.
- `/` — заглавная.

Деплой: Cloudflare API `PUT /accounts/{id}/workers/scripts/boxnumber-site` (multipart: metadata + worker.js) — делается через коннектор Cloudflare в Claude; при изменении кода задеплоить заново.
