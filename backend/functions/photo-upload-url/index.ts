// POST { item_id } → подписанные ссылки для загрузки фото (1600 px) и превью (320 px) вещи в R2.
// Доступ: только тот, кто может редактировать место (place_role = 'edit').
import { json, presign, userClient, UUID } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const { item_id } = await req.json().catch(() => ({}));
  if (typeof item_id !== "string" || !UUID.test(item_id)) return json({ error: "item_id" }, 400);

  const sb = userClient(req);
  const { data: item, error } = await sb.from("items").select("id, place_id").eq("id", item_id).is("deleted_at", null).single();
  if (error || !item) return json({ error: "not_found" }, 404);
  const { data: role } = await sb.rpc("place_role", { p_place: item.place_id });
  if (role !== "edit") return json({ error: "forbidden" }, 403);

  const id = item_id.toLowerCase();
  const photoKey = `items/${id}/photo.jpg`;
  const thumbKey = `items/${id}/thumb.jpg`;
  return json({
    photo_key: photoKey,
    photo_url: await presign(photoKey, "PUT", 900),
    thumb_key: thumbKey,
    thumb_url: await presign(thumbKey, "PUT", 900),
  });
});
