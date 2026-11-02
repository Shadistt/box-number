-- Карточка места (02.11.2026): пометки §13 и «Для описи» места.
-- value — своя стоимость места: если пусто, в итог идёт сумма по вещам; своя заменяет сумму, цены вещей не трогает.
alter table places
  add column if not exists fragile boolean not null default false,
  add column if not exists open_first boolean not null default false,
  add column if not exists weight_kg numeric(8,2) check (weight_kg is null or weight_kg >= 0),
  add column if not exists length_cm int check (length_cm is null or length_cm between 1 and 1000),
  add column if not exists width_cm int check (width_cm is null or width_cm between 1 and 1000),
  add column if not exists height_cm int check (height_cm is null or height_cm between 1 and 1000),
  add column if not exists value numeric(12,2) check (value is null or value >= 0),
  add column if not exists value_currency text check (value_currency is null or value_currency ~ '^[A-Z]{3}$');
