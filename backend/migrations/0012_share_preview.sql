-- Публичный предпросмотр места по коду ссылки — для веб-страницы boxnumber.co/b/<код> (у получателя может не быть
-- приложения). Отдаёт только название, номер, тип, число вещей и имя владельца; ни пароля, ни содержимого.
-- Вызывается анонимно (anon) из Cloudflare Worker. Код ссылки — 11 случайных символов, перебор нереален.
create or replace function share_preview(p_code text)
returns table (number text, title text, kind place_kind, items int, owner_name text, password boolean)
language sql stable security definer set search_path = public as $$
  select p.number, p.title, p.kind,
         (select count(*)::int from items i where i.place_id = p.id and i.deleted_at is null),
         coalesce(nullif(trim(pr.first_name || ' ' || pr.last_name), ''), 'Пользователь Box Nº'),
         s.password_enabled
  from place_shares s
  join places p on p.id = s.place_id and p.deleted_at is null
  join moves m on m.id = p.move_id and m.deleted_at is null
  join profiles pr on pr.id = m.owner_id
  where s.link_code = p_code and s.link_enabled
$$;

revoke all on function share_preview(text) from public;
grant execute on function share_preview(text) to anon, authenticated;
