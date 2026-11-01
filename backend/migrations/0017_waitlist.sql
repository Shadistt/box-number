-- 0017: подписка «Сообщить о запуске» с сайта boxnumber.co (01.11.2026).
-- Double opt-in: строка создаётся неподтверждённой, письмо со ссылкой подтверждения шлёт Edge Function `waitlist`.
-- Пишет и читает только функция сервисным ключом: RLS включён, политик нет, у anon/authenticated прав нет.
create table if not exists waitlist (
  id               uuid primary key default gen_random_uuid(),
  email            text not null,
  locale           text not null default 'en',      -- язык страницы, на котором подписались; на нём же письмо о запуске
  country          text,                             -- страна по IP (Cloudflare), только для статистики
  source           text,                             -- откуда форма: 'site'
  token            uuid not null default gen_random_uuid(), -- для ссылок «подтвердить» и «отписаться»
  ip_hash          text,                             -- sha256(соль + IP) — лимит частоты, сам IP не храним
  created_at       timestamptz not null default now(),
  confirm_sent_at  timestamptz,
  confirmed_at     timestamptz,
  unsubscribed_at  timestamptz,
  notified_at      timestamptz                       -- когда отправили письмо о запуске
);
create unique index if not exists waitlist_email_key on waitlist (lower(email));
create unique index if not exists waitlist_token_key on waitlist (token);
create index if not exists waitlist_ip_time on waitlist (ip_hash, created_at desc);

alter table waitlist enable row level security;
revoke all on waitlist from anon, authenticated;

-- Служебные настройки для функций (ключ сайта, соль). Только сервисный ключ.
create table if not exists app_config (
  key   text primary key,
  value text not null
);
alter table app_config enable row level security;
revoke all on app_config from anon, authenticated;
-- Значения вставлены при выкатке (не в репозитории):
-- insert into app_config values ('waitlist_site_key', '<случайная строка>'), ('waitlist_salt', '<случайная строка>');
