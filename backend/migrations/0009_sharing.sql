-- 0009: §8 «Поделиться местом» и §9 «Кто видит переезд» / Семья

-- ---------- семья ----------
alter table families
  add column if not exists auto_share boolean not null default true,        -- новые места переезда открываются семье сами
  add column if not exists auto_role access_role not null default 'edit';  -- роль по умолчанию для новых мест

-- Семья владельца: создаётся при первом обращении; владелец сам — участник (так работает my_family_id()).
create or replace function my_family() returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare fid uuid;
begin
  select family_id into fid from family_members where user_id = auth.uid() and status = 'active' limit 1;
  if fid is not null then return fid; end if;
  insert into families (owner_id) values (auth.uid()) returning id into fid;
  insert into family_members (family_id, user_id, status, role) values (fid, auth.uid(), 'active', 'edit');
  return fid;
end $$;

-- Приглашения по email: строки с invited_email. При входе пользователя с таким email — привязываем.
create or replace function claim_invites() returns int
language plpgsql volatile security definer set search_path = public as $$
declare e text; n int := 0; c int; r record;
begin
  select lower(email) into e from auth.users where id = auth.uid();
  if e is null then return 0; end if;
  -- в семью — только если ещё не в семье (один пользователь — одна семья)
  if not exists (select 1 from family_members where user_id = auth.uid()) then
    for r in select id from family_members where lower(invited_email) = e and user_id is null order by created_at limit 1 loop
      update family_members set user_id = auth.uid(), status = 'active', invited_email = null where id = r.id; n := n + 1;
    end loop;
  end if;
  delete from family_members where lower(invited_email) = e and user_id is null;   -- остальные приглашения в семьи сгорают
  update move_access set user_id = auth.uid(), status = 'active', invited_email = null
    where lower(invited_email) = e and user_id is null
    and not exists (select 1 from move_access m2 where m2.move_id = move_access.move_id and m2.user_id = auth.uid());
  get diagnostics c = row_count; n := n + c;
  update place_access set user_id = auth.uid(), status = 'active', invited_email = null
    where lower(invited_email) = e and user_id is null
    and not exists (select 1 from place_access p2 where p2.place_id = place_access.place_id and p2.user_id = auth.uid());
  return n;
end $$;

-- Профили видны: себе, семье, тем, с кем есть общие переезды/места (имя и аватар в списках доступа).
drop policy if exists "profile: self read" on profiles;
create policy "profile: read" on profiles for select using (
  id = auth.uid()
  or (my_family_id() is not null and id in (select user_id from family_members where family_id = my_family_id()))
  or id in (select owner_id from families where id = my_family_id())
  or id in (select user_id from move_access where move_id in (select id from moves where owner_id = auth.uid()))
  or id in (select owner_id from moves where id in (select move_id from move_access where user_id = auth.uid()))
  or id in (select user_id from place_access where place_id in (select id from places where move_id in (select id from moves where owner_id = auth.uid())))
  or id in (select m.owner_id from place_access pa join places p on p.id = pa.place_id join moves m on m.id = p.move_id where pa.user_id = auth.uid())
);

-- Поиск людей по email для «Кого добавить»: возвращает только id/имя/аватар, и только при точном совпадении email.
create or replace function find_profile_by_email(p_email text)
returns table (id uuid, first_name text, last_name text, avatar text, photo text)
language sql stable security definer set search_path = public as $$
  select id, first_name, last_name, avatar, photo from profiles where lower(email) = lower(trim(p_email)) limit 1
$$;

-- ---------- доступ к переезду (§9) ----------
-- Владелец переезда управляет move_access (политика "access: owner" уже есть).
-- Новые места открываются «выбранным автоматически»: доступ к переезду покрывает все его места через move_role().

-- ---------- ссылка на место (§8) ----------
create or replace function set_place_link(p_place uuid, p_enabled boolean, p_role access_role, p_password text)
returns place_shares
language plpgsql volatile security definer set search_path = public as $$
declare s place_shares;
begin
  if place_role(p_place) <> 'edit' then raise exception 'forbidden'; end if;
  insert into place_shares (place_id, link_enabled, link_code, link_role, password_enabled, password_hash)
  values (p_place, p_enabled, substr(replace(replace(encode(extensions.gen_random_bytes(6), 'base64'), '/', 'x'), '+', 'y'), 1, 8),
          p_role, p_password is not null, case when p_password is not null then encode(extensions.digest(p_password, 'sha256'), 'hex') end)
  on conflict (place_id) do update set
    link_enabled = excluded.link_enabled,
    link_role = excluded.link_role,
    -- пароль меняется только когда передан; nil = оставить как было (выключают отдельным update)
    password_enabled = case when excluded.password_hash is not null then true else place_shares.password_enabled end,
    password_hash = coalesce(excluded.password_hash, place_shares.password_hash)
  returning * into s;
  return s;
end $$;

-- Открыть место по ссылке: проверяем код и пароль, даём доступ текущему пользователю, возвращаем место.
create or replace function open_share_link(p_code text, p_password text)
returns table (place_id uuid, move_id uuid, number text, title text, kind place_kind, items int, role access_role, owner_name text)
language plpgsql volatile security definer set search_path = public as $$
declare s place_shares; p places; m moves;
begin
  select * into s from place_shares where link_code = p_code and link_enabled;
  if s is null then raise exception 'link_off' using hint = 'Ссылка выключена или неверна'; end if;
  if s.password_enabled and (p_password is null or encode(extensions.digest(p_password, 'sha256'), 'hex') <> s.password_hash) then
    raise exception 'password' using hint = 'Неверный пароль';
  end if;
  select * into p from places where id = s.place_id and deleted_at is null;
  if p is null then raise exception 'not_found'; end if;
  select * into m from moves where id = p.move_id;
  if m.owner_id <> auth.uid() then
    insert into place_access (place_id, user_id, role, status, granted_by, last_opened_at)
    values (p.id, auth.uid(), s.link_role, 'active', m.owner_id, now())
    on conflict (place_id, user_id) do update set role = greatest(place_access.role, excluded.role), status = 'active', last_opened_at = now();
    update places set shared = true where id = p.id;
  end if;
  return query select p.id, p.move_id, p.number, p.title, p.kind,
    (select count(*)::int from items i where i.place_id = p.id and i.deleted_at is null),
    s.link_role, (select nullif(trim(pr.first_name || ' ' || pr.last_name), '') from profiles pr where pr.id = m.owner_id);
end $$;

-- Недавно делились: с кем я открывал места (для раздела «Недавно делились»).
create or replace function recent_shares()
returns table (user_id uuid, last_at timestamptz)
language sql stable security definer set search_path = public as $$
  select pa.user_id, max(pa.created_at) from place_access pa
   join places p on p.id = pa.place_id join moves m on m.id = p.move_id
   where m.owner_id = auth.uid() and pa.user_id is not null and pa.user_id <> auth.uid()
   group by pa.user_id order by 2 desc limit 20
$$;

-- place_access: тот, у кого есть доступ, может закрыть его себе.
create policy "paccess: leave" on place_access for delete using (user_id = auth.uid());
-- place_shares читает тот, кто видит место (чтобы показать «Общая»); пишет — редактор (политика есть).
create policy "shares: read" on place_shares for select using (place_role(place_id) is not null);

grant execute on function my_family(), claim_invites(), find_profile_by_email(text), set_place_link(uuid, boolean, access_role, text),
  open_share_link(text, text), recent_shares() to authenticated;
