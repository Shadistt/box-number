# Box Nº · backend (Supabase)

Проект `zolpdtkhfndravxisuzs` (eu-west-3). Файлы — Cloudflare R2, бакет `boxno-photos`.

## Миграции

`migrations/0001_moves.sql` — применена. Следующие — `0002_…`, применяются через SQL-редактор или Management API.

## Edge Functions

- `photo-upload-url` — `POST { item_id }` → подписанные PUT-ссылки на `items/<id>/photo.jpg` и `thumb.jpg` (15 мин). Только роль `edit`.
- `photo-view-url` — `POST { key }` → подписанная GET-ссылка (1 час). Любой, кто видит вещь.

Обе задеплоены. Деплой из репозитория:

```
supabase functions deploy photo-upload-url photo-view-url --project-ref zolpdtkhfndravxisuzs
```

Нужные секреты (Project Settings → Edge Functions → Secrets):

```
R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET=boxno-photos
```

Пока их нет, функции отвечают 500, а приложение хранит фото только локально.
