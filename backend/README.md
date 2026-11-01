# Box Nº · backend (Supabase)

Проект `zolpdtkhfndravxisuzs` (eu-west-3). Файлы — Cloudflare R2, бакет `boxno-photos`.

## Миграции

`migrations/0001_moves.sql` — применена. Следующие — `0002_…`, применяются через SQL-редактор или Management API.

## Edge Functions

- `photo-upload-url` — `POST { item_id }` → подписанные PUT-ссылки на `items/<id>/photo.jpg` и `thumb.jpg` (15 мин). Только роль `edit`.
- `photo-view-url` — `POST { key }` → подписанная GET-ссылка (1 час). Любой, кто видит вещь.
- `avatar-url` — `POST { op: "put" }` → PUT-ссылка на `avatars/<uid>.jpg`; `POST { op: "get", key }` → GET-ссылка (1 час).
- `support-ticket` — `POST { subject, message, device?, screenshots?: [base64 jpeg ≤3] }` → письмо в support@boxnumber.co через Resend (секрет `RESEND_API_KEY`), reply-to — email пользователя.
- `waitlist` — подписка «Сообщить о запуске» с сайта (verify_jwt выключен; пускает только по заголовку `x-site-key` = `app_config.waitlist_site_key`). `join` / `confirm` / `unsubscribe`; письма — Resend, на языке страницы (10 языков). Таблица `waitlist` — миграция 0017; выгрузка для письма о запуске: `confirmed_at is not null and unsubscribed_at is null`.
- `delete-account` — `POST {}` → удаляет файлы R2 аккаунта (`account_object_keys`) и пользователя Auth сервисным ключом (`SUPABASE_SERVICE_ROLE_KEY` есть в окружении функций). Каскад удаляет profiles/moves/places/items.

Деплой без CLI: `SUPABASE_ACCESS_TOKEN=sbp_… functions/deploy.sh <slug…>` (Management API, multipart с `_shared/r2.ts`).

Миграция `0005_settings.sql` применена 30.10.2026 (2FA-поля, `my_usage()`, `account_object_keys()`).

Конфиг Auth (`auth/apply-auth-email.sh`): коды 6 цифр / 15 мин, двойное подтверждение смены email выключено, manual linking включён, шаблон magic_link показывает код (используется для 2FA и подтверждений в настройках).

Обе задеплоены. Деплой из репозитория:

```
supabase functions deploy photo-upload-url photo-view-url --project-ref zolpdtkhfndravxisuzs
```

Нужные секреты (Project Settings → Edge Functions → Secrets):

```
R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET=boxno-photos, R2_JURISDICTION=eu (бакет в EU → хост *.eu.r2.cloudflarestorage.com)
```

Заданы 30.10.2026. Без них функции отвечают 500, а приложение хранит фото только локально.
