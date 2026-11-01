-- «Сейф» (ТЗ §10а): тип места, содержимое которого зашифровано на устройстве ключом владельца.
-- Сервер хранит только шифртекст: items.title_enc (AES-GCM, base64), фото в R2 — зашифрованные байты.
-- Параметры ключа — в профиле: соль, число итераций PBKDF2 и «проверка» (зашифрованная известная строка),
-- чтобы другое устройство владельца могло проверить пароль и вывести тот же ключ. Сам пароль нигде не хранится.
--
-- Шаг 1 (отдельной транзакцией): alter type place_kind add value 'safe';

alter table items add column if not exists title_enc text;
alter table profiles
  add column if not exists safe_salt text,
  add column if not exists safe_verifier text,
  add column if not exists safe_kdf_iter int;

-- Сейф видит и правит только владелец переезда: ни семья, ни доступ к переезду, ни ссылки.
create or replace function is_move_owner(p_move uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from moves where id = p_move and owner_id = auth.uid())
$$;

drop policy "places: read" on places;
create policy "places: read" on places for select
  using (place_role(move_id, id) is not null and (kind <> 'safe' or is_move_owner(move_id)));
drop policy "places: insert" on places;
create policy "places: insert" on places for insert
  with check (move_role(move_id) = 'edit' and (kind <> 'safe' or is_move_owner(move_id)));
drop policy "places: update" on places;
create policy "places: update" on places for update
  using (place_role(move_id, id) = 'edit' and (kind <> 'safe' or is_move_owner(move_id)));

create or replace function place_is_safe(p_place uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from places where id = p_place and kind = 'safe')
$$;

drop policy "items: read" on items;
create policy "items: read" on items for select
  using (place_role(place_id) is not null and (not place_is_safe(place_id) or is_move_owner((select move_id from places where id = place_id))));
drop policy "items: write" on items;
create policy "items: write" on items for insert
  with check (place_role(place_id) = 'edit' and (not place_is_safe(place_id) or is_move_owner((select move_id from places where id = place_id))));
drop policy "items: update" on items;
create policy "items: update" on items for update
  using (place_role(place_id) = 'edit' and (not place_is_safe(place_id) or is_move_owner((select move_id from places where id = place_id))));

-- Ссылкой и доступом к месту сейф не делится.
create or replace function set_place_link(p_place uuid, p_enabled boolean, p_role access_role, p_password text)
returns place_shares
language plpgsql volatile security definer set search_path = public as $$
declare s place_shares;
begin
  if place_role(p_place) <> 'edit' then raise exception 'forbidden'; end if;
  if place_is_safe(p_place) then raise exception 'safe' using hint = 'Сейфом поделиться нельзя'; end if;
  insert into place_shares (place_id, link_enabled, link_code, link_role, password_enabled, password_hash)
  values (p_place, p_enabled, substr(replace(replace(encode(extensions.gen_random_bytes(9), 'base64'), '/', 'x'), '+', 'y'), 1, 11),
          p_role, p_password is not null, case when p_password is not null then encode(extensions.digest(p_password, 'sha256'), 'hex') end)
  on conflict (place_id) do update set
    link_enabled = excluded.link_enabled,
    link_role = excluded.link_role,
    password_enabled = case when excluded.password_hash is not null then true else place_shares.password_enabled end,
    password_hash = coalesce(excluded.password_hash, place_shares.password_hash)
  returning * into s;
  return s;
end $$;

create or replace function share_preview(p_code text)
returns table (number text, title text, kind place_kind, items int, owner_name text, password boolean)
language sql stable security definer set search_path = public as $$
  select p.number, p.title, p.kind,
         (select count(*)::int from items i where i.place_id = p.id and i.deleted_at is null),
         coalesce(nullif(trim(pr.first_name || ' ' || pr.last_name), ''), 'Пользователь Box Nº'),
         s.password_enabled
  from place_shares s
  join places p on p.id = s.place_id and p.deleted_at is null and p.kind <> 'safe'
  join moves m on m.id = p.move_id and m.deleted_at is null
  join profiles pr on pr.id = m.owner_id
  where s.link_code = p_code and s.link_enabled
$$;

-- Доступ к сейфу отдельным людям тоже не выдаётся.
drop policy "paccess: edit" on place_access;
create policy "paccess: edit" on place_access for all
  using (place_role(place_id) = 'edit' and not place_is_safe(place_id))
  with check (place_role(place_id) = 'edit' and not place_is_safe(place_id));
