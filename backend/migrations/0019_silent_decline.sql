-- Тихий отказ и раздел «Приглашения» (02.11.2026).
-- Отказ больше не меняет статус строки доступа: у отправителя строка остаётся pending («ждём ответа»).
-- Факт отказа хранится в отдельной таблице invite_declines, которую видит только получатель.
-- Окно 30 дней: приглашение старше 30 дней без принятия — «истекло» (отправитель может пригласить снова);
-- отказ действует 30 дней — в этот срок повторное приглашение от того же человека на то же тихо не доходит,
-- а получатель может передумать и принять.

create table if not exists invite_declines (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,   -- кто отказал (получатель)
  inviter_id  uuid not null references profiles(id) on delete cascade,
  kind        text not null check (kind in ('family', 'move', 'place')),
  target_id   uuid not null,                                            -- family_id / move_id / place_id
  declined_at timestamptz not null default now(),
  unique (user_id, kind, target_id, inviter_id)
);
alter table invite_declines enable row level security;
drop policy if exists "declines: own read" on invite_declines;
create policy "declines: own read" on invite_declines for select using (user_id = auth.uid());

create or replace function declined_recently(p_user uuid, p_inviter uuid, p_kind text, p_target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from invite_declines d where d.user_id = p_user and d.inviter_id = p_inviter
                  and d.kind = p_kind and d.target_id = p_target and d.declined_at > now() - interval '30 days')
$$;

-- Перенос старых отказов (status = 'declined', 0016) в новую схему.
insert into invite_declines (user_id, inviter_id, kind, target_id, declined_at)
  select user_id, granted_by, 'move', move_id, now() from move_access where status = 'declined' and user_id is not null and granted_by is not null
  on conflict do nothing;
insert into invite_declines (user_id, inviter_id, kind, target_id, declined_at)
  select user_id, granted_by, 'place', place_id, now() from place_access where status = 'declined' and user_id is not null and granted_by is not null
  on conflict do nothing;
insert into invite_declines (user_id, inviter_id, kind, target_id, declined_at)
  select fm.user_id, coalesce(fm.invited_by, f.owner_id), 'family', fm.family_id, now()
  from family_members fm join families f on f.id = fm.family_id where fm.status = 'declined' and fm.user_id is not null
  on conflict do nothing;
update move_access set status = 'pending' where status = 'declined';
update place_access set status = 'pending' where status = 'declined';
update family_members set status = 'pending' where status = 'declined';

-- ---------- страж: вставка ----------
create or replace function invite_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare inviter uuid; n int; k text; tgt uuid;
begin
  if tg_table_name = 'family_members' then
    if new.user_id = auth.uid() then return new; end if;            -- своя строка (my_family)
    new.invited_by := coalesce(new.invited_by, auth.uid()); inviter := new.invited_by; k := 'family'; tgt := new.family_id;
  elsif tg_table_name = 'move_access' then
    new.granted_by := coalesce(new.granted_by, auth.uid()); inviter := new.granted_by; k := 'move'; tgt := new.move_id;
  else
    new.granted_by := coalesce(new.granted_by, auth.uid()); inviter := new.granted_by; k := 'place'; tgt := new.place_id;
  end if;
  if is_blocked(inviter, new.user_id, new.invited_email) then return null; end if;
  if current_setting('boxno.consent', true) = '1' then return new; end if;
  -- отказал меньше 30 дней назад — тихо не создаём (отправитель видит «ждём ответа» по старой строке или ничего)
  if new.user_id is not null and declined_recently(new.user_id, inviter, k, tgt) then return null; end if;
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

-- ---------- страж: изменение (повторное приглашение через upsert, смена роли) ----------
-- Отправитель не может сам перевести ожидающее приглашение в «active»; повторное приглашение после отказа
-- (в течение 30 дней) или от заблокированного — тихо игнорируется; истёкшее (старше 30 дней) — перезапускается.
drop trigger if exists move_access_declined on move_access;
drop trigger if exists place_access_declined on place_access;
drop trigger if exists family_members_declined on family_members;
drop function if exists invite_keep_declined();

create or replace function invite_reguard() returns trigger
language plpgsql security definer set search_path = public as $$
declare inviter uuid; k text; tgt uuid;
begin
  if coalesce(current_setting('boxno.consent', true), '') = '1' then return new; end if;
  if old.status = 'active' then new.status := 'active'; return new; end if;     -- смена роли у принятого
  if tg_table_name = 'family_members' then inviter := coalesce(old.invited_by, auth.uid()); k := 'family'; tgt := old.family_id;
  elsif tg_table_name = 'move_access' then inviter := coalesce(old.granted_by, auth.uid()); k := 'move'; tgt := old.move_id;
  else inviter := coalesce(old.granted_by, auth.uid()); k := 'place'; tgt := old.place_id; end if;
  if old.user_id is not null and (is_blocked(inviter, old.user_id, null) or declined_recently(old.user_id, inviter, k, tgt)) then
    return old;                                                                  -- тихо: ничего не меняется
  end if;
  if old.created_at < now() - interval '30 days' then new.created_at := now(); end if;   -- истёкшее — заново
  if tg_table_name in ('move_access', 'place_access') and old.user_id is not null and same_family(inviter, old.user_id) then
    new.status := 'active';
  else
    new.status := old.status;                                                    -- pending/invited остаётся
  end if;
  return new;
end $$;

drop trigger if exists move_access_reguard on move_access;
create trigger move_access_reguard before update on move_access for each row execute function invite_reguard();
drop trigger if exists place_access_reguard on place_access;
create trigger place_access_reguard before update on place_access for each row execute function invite_reguard();
drop trigger if exists family_members_reguard on family_members;
create trigger family_members_reguard before update on family_members for each row execute function invite_reguard();

-- «Пригласить снова» у отправителя (истёкшее приглашение): перезапуск срока; отказ/блок — тихо ничего.
create or replace function reinvite(p_kind text, p_id uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if p_kind = 'family' then
    update family_members set created_at = created_at where id = p_id and invited_by = auth.uid() and status <> 'active';
  elsif p_kind = 'move' then
    update move_access set created_at = created_at where id = p_id and granted_by = auth.uid() and status <> 'active';
  elsif p_kind = 'place' then
    update place_access set created_at = created_at where id = p_id and granted_by = auth.uid() and status <> 'active';
  end if;
end $$;

-- ---------- все приглашения получателя (раздел «Приглашения») ----------
-- state: pending | accepted | declined | expired | blocked
drop function if exists my_invitations();
create or replace function my_invitations()
returns table (kind text, id uuid, inviter_id uuid, inviter_name text, inviter_email text, title text, role access_role,
               created_at timestamptz, state text, days_left int)
language sql stable security definer set search_path = public as $$
  with raw as (
    select 'family'::text kind, fm.id, coalesce(fm.invited_by, f.owner_id) inviter, null::text title, fm.role, fm.created_at, fm.status::text st, fm.family_id tgt
      from family_members fm join families f on f.id = fm.family_id
     where fm.user_id = auth.uid() and f.owner_id <> auth.uid() and fm.status in ('pending', 'active')
    union all
    select 'move', ma.id, ma.granted_by,
           coalesce(nullif(m.title, ''), nullif(m.from_city, '') || ' → ' || coalesce((select name from move_destinations d where d.move_id = m.id and d.deleted_at is null order by position limit 1), '…')),
           ma.role, ma.created_at, ma.status::text, ma.move_id
      from move_access ma join moves m on m.id = ma.move_id
     where ma.user_id = auth.uid() and ma.granted_by is not null and ma.granted_by <> auth.uid() and m.deleted_at is null and ma.status in ('pending', 'active')
    union all
    select 'place', pa.id, pa.granted_by, '№ ' || p.number || coalesce(' · ' || nullif(p.title, ''), ''), pa.role, pa.created_at, pa.status::text, pa.place_id
      from place_access pa join places p on p.id = pa.place_id
     where pa.user_id = auth.uid() and pa.granted_by is not null and pa.granted_by <> auth.uid() and p.deleted_at is null and pa.status in ('pending', 'active')
  ), st as (
    select r.*, pr.email, coalesce(nullif(trim(pr.first_name || ' ' || pr.last_name), ''), pr.email) nm,
           (select d.declined_at from invite_declines d where d.user_id = auth.uid() and d.inviter_id = r.inviter and d.kind = r.kind and d.target_id = r.tgt) dec,
           exists (select 1 from blocks b where b.blocker_id = auth.uid() and (b.blocked_user_id = r.inviter or lower(b.blocked_email) = lower(pr.email))) blk
      from raw r join profiles pr on pr.id = r.inviter
  )
  select kind, id, inviter, nm, email, title, role, created_at,
         case when st = 'active' then 'accepted'
              when blk then 'blocked'
              when dec is not null and dec > now() - interval '30 days' then 'declined'
              when dec is not null or created_at < now() - interval '30 days' then 'expired'
              else 'pending' end,
         case when st = 'active' then null
              when dec is not null then greatest(0, 30 - extract(day from now() - dec)::int)
              else greatest(0, 30 - extract(day from now() - created_at)::int) end
    from st
  union all   -- блокировки, к которым уже нет приглашений
  select 'block', b.id, b.blocked_user_id, coalesce(nullif(trim(coalesce(pr.first_name, '') || ' ' || coalesce(pr.last_name, '')), ''), b.blocked_email),
         b.blocked_email, null, null, b.created_at, 'blocked', null
    from blocks b left join profiles pr on pr.id = b.blocked_user_id
   where b.blocker_id = auth.uid()
     and not exists (select 1 from st where st.blk and (st.inviter = b.blocked_user_id or lower(st.email) = lower(b.blocked_email)))
  order by 8 desc
$$;

-- ---------- ответы получателя ----------
create or replace function respond_invitation(p_kind text, p_id uuid, p_accept boolean) returns void
language plpgsql volatile security definer set search_path = public as $$
declare inviter uuid; tgt uuid; fam uuid; fam_id uuid; created timestamptz; dec timestamptz;
begin
  if p_kind = 'family' then
    select coalesce(fm.invited_by, f.owner_id), fm.family_id, fm.created_at into inviter, tgt, created from family_members fm join families f on f.id = fm.family_id
     where fm.id = p_id and fm.user_id = auth.uid() and fm.status = 'pending';
  elsif p_kind = 'move' then
    select granted_by, move_id, created_at into inviter, tgt, created from move_access where id = p_id and user_id = auth.uid() and status = 'pending';
  elsif p_kind = 'place' then
    select granted_by, place_id, created_at into inviter, tgt, created from place_access where id = p_id and user_id = auth.uid() and status = 'pending';
  end if;
  if inviter is null then return; end if;

  if not p_accept then
    insert into invite_declines (user_id, inviter_id, kind, target_id) values (auth.uid(), inviter, p_kind, tgt)
      on conflict (user_id, kind, target_id, inviter_id) do update set declined_at = now();
  else
    -- принять можно ждущее или отклонённое меньше 30 дней назад; истёкшее — нет
    select declined_at into dec from invite_declines where user_id = auth.uid() and inviter_id = inviter and kind = p_kind and target_id = tgt;
    if (dec is not null and dec <= now() - interval '30 days') or (dec is null and created < now() - interval '30 days') then return; end if;
    delete from invite_declines where user_id = auth.uid() and inviter_id = inviter and kind = p_kind and target_id = tgt;
    perform set_config('boxno.consent', '1', true);
    if p_kind = 'family' then perform accept_family(p_id);
    elsif p_kind = 'move' then update move_access set status = 'active' where id = p_id;
    else update place_access set status = 'active' where id = p_id; end if;
    perform set_config('boxno.consent', '0', true);
  end if;

  -- переезд + семья от одного человека (ТЗ §9): отвечаем на оба приглашения разом
  if p_kind = 'move' then
    select family_id into fam_id from family_members where user_id = inviter and status = 'active' limit 1;
    select fm.id into fam from family_members fm where fm.user_id = auth.uid() and fm.status = 'pending' and fm.family_id = fam_id;
    if fam is not null then perform respond_invitation('family', fam, p_accept); end if;
  end if;
end $$;

-- «Отменить» сразу после отказа и «Принять» из раздела — одно и то же: снять отказ.
create or replace function undo_decline(p_kind text, p_id uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
declare inviter uuid; tgt uuid;
begin
  if p_kind = 'family' then select coalesce(fm.invited_by, f.owner_id), fm.family_id into inviter, tgt from family_members fm join families f on f.id = fm.family_id where fm.id = p_id and fm.user_id = auth.uid();
  elsif p_kind = 'move' then select granted_by, move_id into inviter, tgt from move_access where id = p_id and user_id = auth.uid();
  else select granted_by, place_id into inviter, tgt from place_access where id = p_id and user_id = auth.uid(); end if;
  delete from invite_declines where user_id = auth.uid() and inviter_id = inviter and kind = p_kind and target_id = tgt;
end $$;

-- «Выйти» из принятого: доступ закрывается (семья — выход из семьи; пустая семья не создаётся заново до нужды).
create or replace function leave_access(p_kind text, p_id uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if p_kind = 'family' then delete from family_members where id = p_id and user_id = auth.uid() and status = 'active'
                            and family_id not in (select id from families where owner_id = auth.uid());
  elsif p_kind = 'move' then delete from move_access where id = p_id and user_id = auth.uid();
  elsif p_kind = 'place' then delete from place_access where id = p_id and user_id = auth.uid(); end if;
end $$;

-- Блокировка: его ждущие приглашения ко мне — отказ (можно передумать в течение 30 дней после разблокировки).
create or replace function block_user(p_email text) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid; bid uuid; e text := lower(trim(p_email));
begin
  select id into uid from profiles where lower(email) = e;
  if uid = auth.uid() then raise exception 'self'; end if;
  insert into blocks (blocker_id, blocked_user_id, blocked_email) values (auth.uid(), uid, e)
    on conflict (blocker_id, blocked_email) do update set blocked_user_id = excluded.blocked_user_id
    returning id into bid;
  if uid is not null then
    insert into invite_declines (user_id, inviter_id, kind, target_id)
      select auth.uid(), uid, 'move', move_id from move_access where user_id = auth.uid() and status = 'pending' and granted_by = uid
      union all select auth.uid(), uid, 'place', place_id from place_access where user_id = auth.uid() and status = 'pending' and granted_by = uid
      union all select auth.uid(), uid, 'family', family_id from family_members where user_id = auth.uid() and status = 'pending' and invited_by = uid
      on conflict (user_id, kind, target_id, inviter_id) do update set declined_at = now();
  end if;
  return bid;
end $$;

grant execute on function my_invitations(), respond_invitation(text, uuid, boolean), undo_decline(text, uuid),
  leave_access(text, uuid), reinvite(text, uuid), block_user(text) to authenticated;
