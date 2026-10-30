-- 0007: фото места хранится в places.number_photo (places/<id>/photo.jpg); превью — рядом, учитываем при удалении аккаунта.
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
  select replace(p.number_photo, '/photo.jpg', '/thumb.jpg') from places p join moves m on m.id = p.move_id
   where m.owner_id = p_user and p.number_photo like '%/photo.jpg'
  union all
  select pr.photo from profiles pr where pr.id = p_user and pr.photo is not null;
$$;
