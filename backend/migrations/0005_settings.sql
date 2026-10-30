-- 0005: настройки и аккаунт (§10)
-- Двухфакторная защита: флаг и дата последней проверки кодом (код на email каждые 30 дней — проверяет приложение).
alter table profiles
  add column if not exists two_factor boolean not null default false,
  add column if not exists two_factor_verified_at timestamptz;

-- Сводка для шапки настроек: сколько у меня мест и фото (по моим переездам).
create or replace function my_usage() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'places', (select count(*) from places p join moves m on m.id = p.move_id
               where m.owner_id = auth.uid() and m.deleted_at is null and p.deleted_at is null),
    'photos', (select count(*) from items i join places p on p.id = i.place_id join moves m on m.id = p.move_id
               where m.owner_id = auth.uid() and m.deleted_at is null and p.deleted_at is null
                 and i.deleted_at is null and i.photo is not null),
    'synced_at', (select max(greatest(m.updated_at, coalesce(p.updated_at, m.updated_at)))
                  from moves m left join places p on p.move_id = m.id where m.owner_id = auth.uid())
  );
$$;
grant execute on function my_usage() to authenticated;

-- Ключи R2-объектов аккаунта — для удаления аккаунта (service_role).
create or replace function account_object_keys(p_user uuid) returns setof text
language sql stable security definer set search_path = public as $$
  select i.photo from items i join places p on p.id = i.place_id join moves m on m.id = p.move_id
   where m.owner_id = p_user and i.photo is not null
  union all
  select i.thumb from items i join places p on p.id = i.place_id join moves m on m.id = p.move_id
   where m.owner_id = p_user and i.thumb is not null
  union all
  select p.number_photo from places p join moves m on m.id = p.move_id
   where m.owner_id = p_user and p.number_photo is not null
  union all
  select pr.avatar from profiles pr where pr.id = p_user and pr.avatar not like 'preset:%';
$$;
revoke execute on function account_object_keys(uuid) from public, anon, authenticated;
grant execute on function account_object_keys(uuid) to service_role;
