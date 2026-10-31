-- 0011: защита ссылок на место от перебора.
-- Журнал попыток: кто, какой код, когда, успех. По нему — лимиты и пометка владельцу.
create table if not exists share_attempts (
  id          bigserial primary key,
  user_id     uuid not null,
  code        text not null,
  ok          boolean not null,
  reason      text,                    -- link_off | password | ok
  created_at  timestamptz not null default now()
);
create index if not exists share_attempts_user_time on share_attempts (user_id, created_at desc);
create index if not exists share_attempts_code_time on share_attempts (code, created_at desc);
alter table share_attempts enable row level security;   -- политик нет: читает/пишет только security definer
-- Код ссылки длиннее: 11 символов (~64 бита) вместо 8.
create or replace function set_place_link(p_place uuid, p_enabled boolean, p_role access_role, p_password text)
returns place_shares
language plpgsql volatile security definer set search_path = public as $$
declare s place_shares;
begin
  if place_role(p_place) <> 'edit' then raise exception 'forbidden'; end if;
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

-- Владельцу: сколько было неверных попыток по ссылке места за 7 дней (пометка «были попытки подбора»).
create or replace function link_failed_attempts(p_place uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from share_attempts a join place_shares s on s.link_code = a.code
   where s.place_id = p_place and not a.ok and a.reason = 'password' and a.created_at > now() - interval '7 days'
     and place_role(p_place) = 'edit'
$$;
grant execute on function link_failed_attempts(uuid) to authenticated;
