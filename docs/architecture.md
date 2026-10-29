# Box Nº — архитектура (утверждено 29.10.2026)

- **Порядок работ.** Сначала раздел «Переезд» целиком. Хранение и Посылки — после.
- **Платформы.** Нативно: iOS — Swift + SwiftUI; Android — Kotlin + Compose (после iOS). Десктоп — веб на boxnumber.co.
- **Бэкенд.** Supabase: Postgres, Auth (Apple / Google / email+код), RLS, Realtime, Edge Functions. Проект `zolpdtkhfndravxisuzs`, регион eu-west-3.
- **Файлы.** Cloudflare R2, бакет `boxno-photos`, отдача через `cdn.boxnumber.co`. Supabase Storage не используется.
- **Письма.** Resend или Postmark.
- **Подписки.** StoreKit 2 / Google Play Billing, семейный доступ Apple включён. Один тариф Plus (месяц/год). После отмены — только просмотр.
- **Фото.** 1 600 px + превью 320 px делаются на устройстве; в базе только ключ `{user}/{box}/{photo}`; загрузка и просмотр по подписанным URL из Edge Functions (10 мин / 1 час).
- **Ключи.** `sb_publishable_…` — в приложении. `sb_secret_…`, R2-ключи, токены — только в секретах Supabase. В репозиторий не попадают.
