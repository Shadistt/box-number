-- Карточки переездов на главном (02.11.2026, вариант A): кто ещё в переезде.
-- Для каждого видимого мне переезда: владелец (is_owner) и все с активным доступом; меня самого не возвращаем.
create or replace function move_people()
returns table (move_id uuid, user_id uuid, role access_role, is_owner boolean,
               first_name text, last_name text, email text, avatar text, photo text)
language sql stable security definer set search_path = public as $$
  with mine as (
    select m.id from moves m
     where m.deleted_at is null and (m.owner_id = auth.uid()
       or exists (select 1 from move_access a where a.move_id = m.id and a.user_id = auth.uid() and a.status = 'active'))
  ), people as (
    select m.id move_id, m.owner_id user_id, 'edit'::access_role role, true is_owner
      from moves m join mine on mine.id = m.id
    union all
    select a.move_id, a.user_id, a.role, false
      from move_access a join mine on mine.id = a.move_id
     where a.status = 'active' and a.user_id is not null
  )
  select pe.move_id, pe.user_id, pe.role, pe.is_owner, p.first_name, p.last_name, p.email, p.avatar, p.photo
    from people pe join profiles p on p.id = pe.user_id
   where pe.user_id <> auth.uid()
$$;
grant execute on function move_people() to authenticated;
