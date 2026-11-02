-- Сейф — отдельная сущность (02.11.2026): создаётся только пустым и не превращается в другой тип;
-- обычное место нельзя сделать сейфом. Защита на сервере, чтобы не обойти из старых сборок.
create or replace function place_kind_guard() returns trigger
language plpgsql as $$
begin
  if new.kind is distinct from old.kind and (old.kind = 'safe' or new.kind = 'safe') then
    raise exception 'safe_kind_locked' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists place_kind_guard on places;
create trigger place_kind_guard before update of kind on places for each row execute function place_kind_guard();
