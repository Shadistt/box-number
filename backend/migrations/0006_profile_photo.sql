-- 0006: своё фото профиля хранится отдельно от выбранной аватарки — можно переключаться на пресет и обратно.
alter table profiles add column if not exists photo text;   -- ключ R2 avatars/<uid>.jpg
-- avatar: 'preset:<name>' или 'photo' (показывать своё фото)
update profiles set photo = avatar, avatar = 'photo' where avatar like 'avatars/%';

-- ключи файлов аккаунта: фото профиля теперь в колонке photo
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
  select pr.photo from profiles pr where pr.id = p_user and pr.photo is not null;
$$;
