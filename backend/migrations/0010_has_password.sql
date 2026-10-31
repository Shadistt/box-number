-- 0010: признак «пароль задан» (identities не отражают пароль у Apple/Google-пользователей)
alter table profiles add column if not exists has_password boolean not null default false;
update profiles p set has_password = (u.encrypted_password is not null and u.encrypted_password <> '') from auth.users u where u.id = p.id;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, first_name, last_name, has_password)
  values (new.id, coalesce(new.email, ''),
          coalesce(new.raw_user_meta_data->>'first_name', ''),
          coalesce(new.raw_user_meta_data->>'last_name', ''),
          new.encrypted_password is not null and new.encrypted_password <> '');
  return new;
end $$;

create or replace function sync_profile_from_auth() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update profiles set
    has_password = (new.encrypted_password is not null and new.encrypted_password <> ''),
    email = coalesce(new.email, email)
  where id = new.id;
  return new;
end $$;
drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated after update of encrypted_password, email on auth.users
  for each row execute function sync_profile_from_auth();
