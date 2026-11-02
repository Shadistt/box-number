-- Документы (03.11.2026): камера сама узнаёт лист, страницы складываются в PDF.
-- doc — ключ PDF в R2 (items/<id>/doc.pdf; у сейфа — зашифрованные байты), doc_pages — число страниц.
-- Фото первой страницы лежит в photo/thumb, как у обычной вещи (сетка и поиск не меняются).
alter table items
  add column if not exists doc text,
  add column if not exists doc_pages int check (doc_pages is null or doc_pages between 1 and 1000);
