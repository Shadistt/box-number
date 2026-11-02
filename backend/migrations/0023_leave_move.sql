-- Участник (не владелец) может убрать чужой переезд из своего списка: удаляется только его доступ.
create or replace function leave_move(p_move uuid) returns void
language sql volatile security definer set search_path = public as $$
  delete from move_access where move_id = p_move and user_id = auth.uid();
  delete from place_access where user_id = auth.uid() and place_id in (select id from places where move_id = p_move);
$$;
grant execute on function leave_move(uuid) to authenticated;
