-- Box Nº · раздел «Переезд» · миграция 0001
-- Утверждено 29.10.2026

create extension if not exists pgcrypto;

-- ---------- типы ----------
create type plan_kind       as enum ('free', 'plus');
create type access_role     as enum ('view', 'edit');
create type member_status   as enum ('invited', 'active');
create type move_status     as enum ('active', 'archived');
create type place_kind      as enum ('box', 'folder', 'container', 'suitcase', 'bag', 'wardrobe', 'large', 'custom');
create type place_status    as enum ('open', 'packed', 'unpacking');
create type caption_source  as enum ('ai', 'user');

-- ---------- общие вещи ----------
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ---------- пользователи ----------
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  first_name  text not null default '',
  last_name   text not null default '',
  email       text not null,
  avatar      text not null default 'preset:box',   -- ключ R2 или preset:<name>
  plan        plan_kind not null default 'free',
  plan_until  timestamptz,
  locale      text not null default 'ru',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger profiles_updated before update on profiles for each row execute function set_updated_at();

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, first_name, last_name)
  values (new.id, coalesce(new.email, ''),
          coalesce(new.raw_user_meta_data->>'first_name', ''),
          coalesce(new.raw_user_meta_data->>'last_name', ''));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

create table families (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table family_members (
  id             uuid primary key default gen_random_uuid(),
  family_id      uuid not null references families(id) on delete cascade,
  user_id        uuid references profiles(id) on delete cascade,
  invited_email  text,
  status         member_status not null default 'invited',
  role           access_role not null default 'edit',
  created_at     timestamptz not null default now(),
  unique (user_id),                                 -- один пользователь — в одной семье
  check (user_id is not null or invited_email is not null)
);
create index on family_members (family_id);

-- ---------- переезд ----------
create table moves (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references profiles(id) on delete cascade,
  title        text,                                -- null = «Откуда → Куда»
  from_city    text not null default '',
  status       move_status not null default 'active',
  archived_at  timestamptz,
  next_number  integer not null default 1,          -- подсказка следующего номера
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index on moves (owner_id) where deleted_at is null;
create trigger moves_updated before update on moves for each row execute function set_updated_at();

create table move_destinations (
  id          uuid primary key default gen_random_uuid(),
  move_id     uuid not null references moves(id) on delete cascade,
  name        text not null,
  position    smallint not null default 0,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index on move_destinations (move_id);

-- не больше 5 активных направлений на переезд
create or replace function check_destinations_limit() returns trigger language plpgsql as $$
begin
  if (select count(*) from move_destinations where move_id = new.move_id and deleted_at is null) >= 5 then
    raise exception 'destinations_limit' using hint = 'Не больше 5 направлений на переезд';
  end if;
  return new;
end $$;
create trigger move_destinations_limit before insert on move_destinations
  for each row execute function check_destinations_limit();

create table move_access (
  id          uuid primary key default gen_random_uuid(),
  move_id     uuid not null references moves(id) on delete cascade,
  user_id     uuid references profiles(id) on delete cascade,
  invited_email text,
  role        access_role not null default 'view',
  status      member_status not null default 'active',
  granted_by  uuid references profiles(id),
  created_at  timestamptz not null default now(),
  unique (move_id, user_id),
  check (user_id is not null or invited_email is not null)
);
create index on move_access (user_id);

-- ---------- места ----------
create table places (
  id              uuid primary key default gen_random_uuid(),
  move_id         uuid not null references moves(id) on delete cascade,
  number          text not null,                    -- «3», «3б», «12а» — текст, уникален в переезде
  title           text not null default '',
  kind            place_kind not null default 'box',
  custom_kind     text,
  destination_id  uuid references move_destinations(id) on delete set null,
  status          place_status not null default 'open',
  packed_at       timestamptz,
  unpacked_at     timestamptz,
  number_photo    text,                             -- ключ R2, необязательно
  shared          boolean not null default false,
  created_by      uuid references profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  check (status <> 'packed' or destination_id is not null)   -- запаковать без направления нельзя
);
create unique index places_number_unique on places (move_id, lower(number)) where deleted_at is null;
create index on places (move_id) where deleted_at is null;
create trigger places_updated before update on places for each row execute function set_updated_at();

-- выдать следующий свободный номер в переезде
create or replace function next_place_number(p_move uuid) returns text
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update moves set next_number = next_number + 1 where id = p_move returning next_number - 1 into n;
  while exists (select 1 from places where move_id = p_move and deleted_at is null and lower(number) = n::text) loop
    update moves set next_number = next_number + 1 where id = p_move returning next_number - 1 into n;
  end loop;
  return n::text;
end $$;

create table items (
  id              uuid primary key default gen_random_uuid(),
  place_id        uuid not null references places(id) on delete cascade,
  title           text not null default '',
  caption_source  caption_source not null default 'ai',
  photo           text,                             -- ключ R2, 1600 px
  thumb           text,                             -- ключ R2, 320 px
  taken_at        timestamptz,                      -- достали при распаковке
  position        integer not null default 0,
  created_by      uuid references profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index on items (place_id) where deleted_at is null;
create trigger items_updated before update on items for each row execute function set_updated_at();

-- ---------- доступ к одному месту ----------
create table place_shares (
  place_id          uuid primary key references places(id) on delete cascade,
  link_enabled      boolean not null default false,
  link_code         text unique,                    -- boxnumber.co/b/<code>
  link_role         access_role not null default 'view',
  password_enabled  boolean not null default false,
  password_hash     text,
  updated_at        timestamptz not null default now()
);
create trigger place_shares_updated before update on place_shares for each row execute function set_updated_at();

create table place_access (
  id              uuid primary key default gen_random_uuid(),
  place_id        uuid not null references places(id) on delete cascade,
  user_id         uuid references profiles(id) on delete cascade,
  invited_email   text,
  role            access_role not null default 'view',
  status          member_status not null default 'active',
  last_opened_at  timestamptz,
  granted_by      uuid references profiles(id),
  created_at      timestamptz not null default now(),
  unique (place_id, user_id),
  check (user_id is not null or invited_email is not null)
);
create index on place_access (user_id);

-- ---------- права (RLS) ----------
alter table profiles          enable row level security;
alter table families          enable row level security;
alter table family_members    enable row level security;
alter table moves             enable row level security;
alter table move_destinations enable row level security;
alter table move_access       enable row level security;
alter table places            enable row level security;
alter table items             enable row level security;
alter table place_shares      enable row level security;
alter table place_access      enable row level security;

-- помощники
create or replace function my_family_id() returns uuid language sql stable security definer set search_path = public as $$
  select family_id from family_members where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function move_role(p_move uuid) returns access_role
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from moves where id = p_move and owner_id = auth.uid()) then 'edit'::access_role
    else (select role from move_access where move_id = p_move and user_id = auth.uid() and status = 'active')
  end
$$;

create or replace function place_role(p_place uuid) returns access_role
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select move_role(move_id) from places where id = p_place),
    (select role from place_access where place_id = p_place and user_id = auth.uid() and status = 'active')
  )
$$;

-- profiles
create policy "profile: self read"   on profiles for select using (id = auth.uid()
  or (my_family_id() is not null and id in (select user_id from family_members where family_id = my_family_id())));
create policy "profile: self write"  on profiles for update using (id = auth.uid());

-- families
create policy "family: members read"  on families for select using (owner_id = auth.uid() or id = my_family_id());
create policy "family: owner all"     on families for all using (owner_id = auth.uid());
create policy "members: read"         on family_members for select using (family_id = my_family_id() or user_id = auth.uid()
  or family_id in (select id from families where owner_id = auth.uid()));
create policy "members: owner all"    on family_members for all using (family_id in (select id from families where owner_id = auth.uid()));
create policy "members: leave"        on family_members for delete using (user_id = auth.uid());

-- moves
create policy "moves: read"   on moves for select using (move_role(id) is not null);
create policy "moves: insert" on moves for insert with check (owner_id = auth.uid());
create policy "moves: update" on moves for update using (move_role(id) = 'edit');
create policy "moves: delete" on moves for delete using (owner_id = auth.uid());

create policy "dest: read"  on move_destinations for select using (move_role(move_id) is not null);
create policy "dest: write" on move_destinations for all using (move_role(move_id) = 'edit');

create policy "access: read"  on move_access for select using (move_role(move_id) is not null or user_id = auth.uid());
create policy "access: owner" on move_access for all using (move_id in (select id from moves where owner_id = auth.uid()));

-- places / items
create policy "places: read"   on places for select using (place_role(id) is not null);
create policy "places: insert" on places for insert with check (move_role(move_id) = 'edit');
create policy "places: update" on places for update using (place_role(id) = 'edit');
create policy "places: delete" on places for delete using (move_id in (select id from moves where owner_id = auth.uid()));

create policy "items: read"   on items for select using (place_role(place_id) is not null);
create policy "items: write"  on items for insert with check (place_role(place_id) = 'edit');
create policy "items: update" on items for update using (place_role(place_id) = 'edit');
create policy "items: delete" on items for delete using (place_role(place_id) = 'edit');

-- shares: только владелец/редактор места; ссылку по коду проверяет Edge Function через service role
create policy "shares: edit" on place_shares for all using (place_role(place_id) = 'edit');
create policy "paccess: read"  on place_access for select using (place_role(place_id) is not null or user_id = auth.uid());
create policy "paccess: edit"  on place_access for all using (place_role(place_id) = 'edit');

-- ---------- realtime ----------
alter publication supabase_realtime add table moves, move_destinations, move_access, places, items, place_access;
