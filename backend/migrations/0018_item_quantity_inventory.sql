-- Количество у вещи (ТЗ §15) и поля «Для описи» (§16): вес и оценочная стоимость — необязательные.
-- Стоимость хранится как ввели: число + код валюты.
alter table items
  add column if not exists quantity int not null default 1 check (quantity between 1 and 999),
  add column if not exists weight_kg numeric(8,2) check (weight_kg is null or weight_kg >= 0),
  add column if not exists value numeric(12,2) check (value is null or value >= 0),
  add column if not exists value_currency text check (value_currency is null or value_currency ~ '^[A-Z]{3}$');
