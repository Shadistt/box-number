-- Статус «разобрана»: всё достали при распаковке. Место остаётся в истории, но из активных уходит.
alter type place_status add value if not exists 'done';
