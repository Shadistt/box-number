-- Мгновенное обновление у получателя (Supabase Realtime): семья тоже в публикации
-- (move_access, place_access, moves, places, items, move_destinations там с 0001). RLS фильтрует события.
alter publication supabase_realtime add table family_members;
