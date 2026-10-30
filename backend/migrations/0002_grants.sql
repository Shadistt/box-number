-- Права ролей API на таблицы и функции раздела «Переезд». Доступ по строкам ограничивает RLS (0001).
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;
grant select on profiles to anon;                       -- для страницы места по ссылке (позже)
grant execute on all functions in schema public to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
alter default privileges for role postgres in schema public grant select, insert, update, delete on tables to authenticated, service_role;
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;
