-- 0020: «Пригласить снова» в семью может и владелец семьи (у старых строк invited_by пустой).
create or replace function reinvite(p_kind text, p_id uuid) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if p_kind = 'family' then
    update family_members fm set created_at = created_at
     where fm.id = p_id and fm.status <> 'active'
       and (fm.invited_by = auth.uid() or exists (select 1 from families f where f.id = fm.family_id and f.owner_id = auth.uid()));
  elsif p_kind = 'move' then
    update move_access set created_at = created_at where id = p_id and granted_by = auth.uid() and status <> 'active';
  elsif p_kind = 'place' then
    update place_access set created_at = created_at where id = p_id and granted_by = auth.uid() and status <> 'active';
  end if;
end $$;
