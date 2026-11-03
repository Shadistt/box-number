-- Имя и фамилия при регистрации через Google (03.11.2026): Google отдаёт full_name / name, а не first_name / last_name.
-- Берём given/family, если есть; иначе делим полное имя: первое слово — имя, остальное — фамилия.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  full_n text := trim(coalesce(m->>'full_name', m->>'name', ''));
  fn text := coalesce(nullif(m->>'first_name', ''), nullif(m->>'given_name', ''), nullif(split_part(full_n, ' ', 1), ''), '');
  ln text := coalesce(nullif(m->>'last_name', ''), nullif(m->>'family_name', ''),
                      nullif(trim(substr(full_n, length(split_part(full_n, ' ', 1)) + 1)), ''), '');
begin
  insert into profiles (id, email, first_name, last_name, has_password)
  values (new.id, coalesce(new.email, ''), fn, ln,
          new.encrypted_password is not null and new.encrypted_password <> '');
  return new;
end $$;

-- Уже зарегистрированным через Google с пустым именем — заполняем один раз.
update profiles p set
  first_name = split_part(trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name')), ' ', 1),
  last_name  = trim(substr(trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name')),
                 length(split_part(trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name')), ' ', 1)) + 1))
from auth.users u
where u.id = p.id and p.first_name = '' and p.last_name = ''
  and coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '') <> '';
