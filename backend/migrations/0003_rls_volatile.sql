-- Помощники RLS были stable: при insert … returning они не видели новую строку (снимок до вставки),
-- и Postgres отвечал «new row violates row-level security policy». Делаем их volatile
-- и добавляем прямую проверку владельца в политики чтения.
create or replace function my_family_id() returns uuid language sql volatile security definer set search_path = public as $$
  select family_id from family_members where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function move_role(p_move uuid) returns access_role
language sql volatile security definer set search_path = public as $$
  select case
    when exists (select 1 from moves where id = p_move and owner_id = auth.uid()) then 'edit'::access_role
    else (select role from move_access where move_id = p_move and user_id = auth.uid() and status = 'active')
  end
$$;

create or replace function place_role(p_place uuid) returns access_role
language sql volatile security definer set search_path = public as $$
  select coalesce(
    (select move_role(move_id) from places where id = p_place),
    (select role from place_access where place_id = p_place and user_id = auth.uid() and status = 'active')
  )
$$;

drop policy "moves: read" on moves;
create policy "moves: read" on moves for select using (owner_id = auth.uid() or move_role(id) is not null);

drop function if exists whoami();

-- Для самой таблицы places нельзя искать свою же строку по id в момент insert … returning:
-- берём move_id из строки и проверяем доступ по нему.
create or replace function place_role(p_move uuid, p_place uuid) returns access_role
language sql volatile security definer set search_path = public as $$
  select coalesce(
    move_role(p_move),
    (select role from place_access where place_id = p_place and user_id = auth.uid() and status = 'active')
  )
$$;
drop policy "places: read" on places;
drop policy "places: update" on places;
create policy "places: read"   on places for select using (place_role(move_id, id) is not null);
create policy "places: update" on places for update using (place_role(move_id, id) = 'edit');
