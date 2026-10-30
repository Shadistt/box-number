-- 0008: ручной порядок переездов на главном (зажать карточку и перетащить)
alter table moves add column if not exists position integer not null default 0;
