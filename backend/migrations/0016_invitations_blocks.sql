-- Подтверждение приглашений и блокировка (01.11.2026).
-- Статусы member_status: invited (аккаунта ещё нет, ждём по email) → pending (аккаунт есть, ждём «Принять»)
-- → active; declined — отказ (строка остаётся, чтобы повторное приглашение не доходило).
-- Семья — без подтверждения переездов: доступ к переезду/месту внутри одной семьи становится active сразу.
-- Шаг 1 (отдельными транзакциями): alter type member_status add value 'pending'; ... add value 'declined';

alter table family_members add column if not exists invited_by uuid references profiles(id);
-- Один человек активен в одной семье, но приглашения (pending) могут ждать и в других.
alter table family_members drop constraint if exists family_members_user_id_key;
create unique index if not exists family_members_active_user on family_members (user_id) where status = 'active';
create unique index if not exists family_members_family_user on family_members (family_id, user_id) where user_id is not null;

-- ---------- блокировки ----------
create table if not exists blocks (
  id              uuid primary key default gen_random_uuid(),
  blocker_id      uuid not null references profiles(id) on delete cascade,
  blocked_user_id uuid references profiles(id) on delete cascade,
  blocked_email   text not null,
  created_at      timestamptz not null default now(),
  unique (blocker_id, blocked_email)
);
alter table blocks enable row level security;
drop policy if exists "blocks: own" on blocks;
create policy "blocks: own" on blocks for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

create or replace function is_blocked(p_inviter uuid, p_user uuid, p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from blocks b
    where b.blocker_id = coalesce(p_user, (select id from profiles where lower(email) = lower(p_email)))
      and (b.blocked_user_id = p_inviter or lower(b.blocked_email) = (select lower(email) from profiles where id = p_inviter))
  )
$$;

create or replace function same_family(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from family_members a join family_members b on a.family_id = b.family_id
    where a.user_id = p_a and b.user_id = p_b and a.status = 'active' and b.status = 'active'
  )
$$;

-- ---------- страж приглашений ----------
-- Заблокирован → строка тихо не создаётся (приглашающий не узнаёт). Лимит 20 приглашений в сутки.
-- Существующему пользователю — pending, кроме доступа к переезду/месту внутри своей семьи (active).
-- Флаг boxno.consent = '1' ставят функции, где человек сам даёт согласие (открыл ссылку, принял приглашение).
create or replace function invite_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare inviter uuid; n int;
begin
  if tg_table_name = 'family_members' then
    if new.user_id = auth.uid() then return new; end if;            -- своя строка (my_family)
    new.invited_by := coalesce(new.invited_by, auth.uid()); inviter := new.invited_by;
  else
    new.granted_by := coalesce(new.granted_by, auth.uid()); inviter := new.granted_by;
  end if;
  if is_blocked(inviter, new.user_id, new.invited_email) then return null; end if;
  if current_setting('boxno.consent', true) = '1' then return new; end if;
  select (select count(*) from move_access where granted_by = inviter and created_at > now() - interval '1 day')
       + (select count(*) from place_access where granted_by = inviter and created_at > now() - interval '1 day')
       + (select count(*) from family_members where invited_by = inviter and created_at > now() - interval '1 day') into n;
  if n >= 20 then raise exception 'invite_limit' using hint = 'Не больше 20 приглашений в сутки'; end if;
  if new.user_id is not null then
    if tg_table_name in ('move_access', 'place_access') and same_family(inviter, new.user_id) then new.status := 'active';
    else new.status := 'pending'; end if;
  end if;
  return new;
end $$;

-- Отказ не перезаписывается повторным приглашением (upsert … do update).
create or replace function invite_keep_declined() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'declined' and coalesce(current_setting('boxno.consent', true), '') <> '1' then return old; end if;
  return new;
end $$;

drop trigger if exists move_access_guard on move_access;
create trigger move_access_guard before insert on move_access for each row execute function invite_guard();
drop trigger if exists move_access_declined on move_access;
create trigger move_access_declined before update on move_access for each row execute function invite_keep_declined();
drop trigger if exists place_access_guard on place_access;
create trigger place_access_guard before insert on place_access for each row execute function invite_guard();
drop trigger if exists place_access_declined on place_access;
create trigger place_access_declined before update on place_access for each row execute function invite_keep_declined();
drop trigger if exists family_members_guard on family_members;
create trigger family_members_guard before insert on family_members for each row execute function invite_guard();
drop trigger if exists family_members_declined on family_members;
create trigger family_members_declined before update on family_members for each row execute function invite_keep_declined();

-- Открыл ссылку сам — согласие есть: доступ сразу active (тело из 0011 + флаг boxno.consent).
create or replace function open_share_link(p_code text, p_password text)
returns table (place_id uuid, move_id uuid, number text, title text, kind place_kind, items int, role access_role, owner_name text)
language plpgsql volatile security definer set search_path = public as $$
declare s place_shares; p places; m moves; n_hour int; n_fail int;
begin
  -- Лимиты: не больше 30 проверок ссылок в час на аккаунт; 5 неверных по одной ссылке → пауза 15 минут.
  select count(*) into n_hour from share_attempts where user_id = auth.uid() and created_at > now() - interval '1 hour';
  if n_hour >= 30 then raise exception 'rate_limit' using hint = 'Слишком много попыток. Попробуйте через час'; end if;
  select count(*) into n_fail from share_attempts where user_id = auth.uid() and code = p_code and not ok and created_at > now() - interval '15 minutes';
  if n_fail >= 5 then raise exception 'locked' using hint = 'Слишком много неверных паролей. Попробуйте через 15 минут'; end if;

  select * into s from place_shares where link_code = p_code and link_enabled;
  if s is null then
    insert into share_attempts (user_id, code, ok, reason) values (auth.uid(), p_code, false, 'link_off');
    raise exception 'link_off' using hint = 'Ссылка выключена или неверна';
  end if;
  if s.password_enabled and (p_password is null or encode(extensions.digest(p_password, 'sha256'), 'hex') <> s.password_hash) then
    if p_password is not null then insert into share_attempts (user_id, code, ok, reason) values (auth.uid(), p_code, false, 'password'); end if;
    raise exception 'password' using hint = 'Неверный пароль';
  end if;
  insert into share_attempts (user_id, code, ok, reason) values (auth.uid(), p_code, true, 'ok');
  select * into p from places where id = s.place_id and deleted_at is null;
  if p is null then raise exception 'not_found'; end if;
  select * into m from moves where id = p.move_id;
  perform set_config('boxno.consent', '1', true);   -- человек сам открыл ссылку: доступ сразу active, страж не вмешивается
  if m.owner_id <> auth.uid() then
    insert into place_access (place_id, user_id, role, status, granted_by, last_opened_at)
    values (p.id, auth.uid(), s.link_role, 'active', m.owner_id, now())
    on conflict (place_id, user_id) do update set role = greatest(place_access.role, excluded.role), status = 'active', last_opened_at = now();
    update places set shared = true where id = p.id;
  end if;
  perform set_config('boxno.consent', '0', true);
  return query select p.id, p.move_id, p.number, p.title, p.kind,
    (select count(*)::int from items i where i.place_id = p.id and i.deleted_at is null),
    s.link_role, (select nullif(trim(pr.first_name || ' ' || pr.last_name), '') from profiles pr where pr.id = m.owner_id);
end $$;

-- Вход с email, на который звали: приглашения становятся pending (ждут «Принять»), а не active.
create or replace function claim_invites() returns int
language plpgsql volatile security definer set search_path = public as $$
declare e text; n int := 0; c int;
begin
  select lower(email) into e from auth.users where id = auth.uid();
  if e is null then return 0; end if;
  update family_members set user_id = auth.uid(), status = 'pending', invited_email = null
    where lower(invited_email) = e and user_id is null
    and not exists (select 1 from family_members f2 where f2.family_id = family_members.family_id and f2.user_id = auth.uid());
  get diagnostics c = row_count; n := n + c;
  update move_access set user_id = auth.uid(), status = 'pending', invited_email = null
    where lower(invited_email) = e and user_id is null
    and not exists (select 1 from move_access m2 where m2.move_id = move_access.move_id and m2.user_id = auth.uid());
  get diagnostics c = row_count; n := n + c;
  update place_access set user_id = auth.uid(), status = 'pending', invited_email = null
    where lower(invited_email) = e and user_id is null
    and not exists (select 1 from place_access p2 where p2.place_id = place_access.place_id and p2.user_id = auth.uid());
  get diagnostics c = row_count; n := n + c;
  return n;
end $$;

-- ---------- мои приглашения ----------
create or replace function my_invitations()
returns table (kind text, id uuid, inviter_id uuid, inviter_name text, inviter_email text, title text, role access_role, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select 'family', fm.id, coalesce(fm.invited_by, f.owner_id),
         coalesce(nullif(trim(pr.first_name || ' ' || pr.last_name), ''), pr.email), pr.email, null::text, fm.role, fm.created_at
  from family_members fm join families f on f.id = fm.family_id
  join profiles pr on pr.id = coalesce(fm.invited_by, f.owner_id)
  where fm.user_id = auth.uid() and fm.status = 'pending'
  union all
  select 'move', ma.id, ma.granted_by,
         coalesce(nullif(trim(pr.first_name || ' ' || pr.last_name), ''), pr.email), pr.email,
         coalesce(nullif(m.title, ''), nullif(m.from_city, '') || ' → ' || coalesce((select name from move_destinations d where d.move_id = m.id and d.deleted_at is null order by position limit 1), '…')),
         ma.role, ma.created_at
  from move_access ma join moves m on m.id = ma.move_id join profiles pr on pr.id = ma.granted_by
  where ma.user_id = auth.uid() and ma.status = 'pending' and m.deleted_at is null
  union all
  select 'place', pa.id, pa.granted_by,
         coalesce(nullif(trim(pr.first_name || ' ' || pr.last_name), ''), pr.email), pr.email,
         '№ ' || p.number || coalesce(' · ' || nullif(p.title, ''), ''), pa.role, pa.created_at
  from place_access pa join places p on p.id = pa.place_id join profiles pr on pr.id = pa.granted_by
  where pa.user_id = auth.uid() and pa.status = 'pending' and p.deleted_at is null
  order by 8 desc
$$;

-- Принять семью: уйти из прежней (пустую свою — удалить), стать active, активировать доступы от членов этой семьи.
create or replace function accept_family(p_id uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
declare fm family_members; old_fid uuid;
begin
  select * into fm from family_members where id = p_id and user_id = auth.uid();
  if fm is null then return; end if;
  perform set_config('boxno.consent', '1', true);
  for old_fid in select family_id from family_members where user_id = auth.uid() and status = 'active' and family_id <> fm.family_id loop
    delete from family_members where family_id = old_fid and user_id = auth.uid();
    delete from families where id = old_fid and not exists (select 1 from family_members where family_id = old_fid);
  end loop;
  update family_members set status = 'active' where id = p_id;
  update move_access set status = 'active' where user_id = auth.uid() and status = 'pending'
    and granted_by in (select user_id from family_members where family_id = fm.family_id and status = 'active');
  update place_access set status = 'active' where user_id = auth.uid() and status = 'pending'
    and granted_by in (select user_id from family_members where family_id = fm.family_id and status = 'active');
  perform set_config('boxno.consent', '0', true);
end $$;

create or replace function respond_invitation(p_kind text, p_id uuid, p_accept boolean) returns void
language plpgsql volatile security definer set search_path = public as $$
declare inviter uuid; fam uuid;
begin
  perform set_config('boxno.consent', '1', true);
  if p_kind = 'family' then
    if p_accept then perform accept_family(p_id);
    else update family_members set status = 'declined' where id = p_id and user_id = auth.uid() and status = 'pending'; end if;
  elsif p_kind = 'move' then
    select granted_by into inviter from move_access where id = p_id and user_id = auth.uid() and status = 'pending';
    if inviter is null then return; end if;
    update move_access set status = case when p_accept then 'active' else 'declined' end::member_status where id = p_id;
    -- вместе с переездом звали и в семью (ТЗ §9): отвечаем на оба приглашения разом
    select fm.id into fam from family_members fm where fm.user_id = auth.uid() and fm.status = 'pending'
      and fm.family_id = (select family_id from family_members where user_id = inviter and status = 'active' limit 1);
    if fam is not null then
      if p_accept then perform accept_family(fam); else update family_members set status = 'declined' where id = fam; end if;
    end if;
  elsif p_kind = 'place' then
    update place_access set status = case when p_accept then 'active' else 'declined' end::member_status
      where id = p_id and user_id = auth.uid() and status = 'pending';
  end if;
  perform set_config('boxno.consent', '0', true);
end $$;

-- ---------- блокировка ----------
create or replace function block_user(p_email text) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid; bid uuid; e text := lower(trim(p_email));
begin
  select id into uid from profiles where lower(email) = e;
  if uid = auth.uid() then raise exception 'self'; end if;
  insert into blocks (blocker_id, blocked_user_id, blocked_email) values (auth.uid(), uid, e)
    on conflict (blocker_id, blocked_email) do update set blocked_user_id = excluded.blocked_user_id
    returning id into bid;
  perform set_config('boxno.consent', '1', true);
  if uid is not null then   -- его ждущие приглашения ко мне — отклонить
    update move_access set status = 'declined' where user_id = auth.uid() and status = 'pending' and granted_by = uid;
    update place_access set status = 'declined' where user_id = auth.uid() and status = 'pending' and granted_by = uid;
    update family_members set status = 'declined' where user_id = auth.uid() and status = 'pending' and invited_by = uid;
  end if;
  perform set_config('boxno.consent', '0', true);
  return bid;
end $$;

create or replace function my_blocks()
returns table (id uuid, email text, name text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select b.id, b.blocked_email, nullif(trim(coalesce(pr.first_name, '') || ' ' || coalesce(pr.last_name, '')), ''), b.created_at
  from blocks b left join profiles pr on pr.id = b.blocked_user_id
  where b.blocker_id = auth.uid() order by b.created_at desc
$$;

grant execute on function my_invitations(), respond_invitation(text, uuid, boolean), accept_family(uuid), block_user(text), my_blocks() to authenticated;
