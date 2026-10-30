// POST { item_id } | { place_id } → подписанные ссылки для загрузки фото (1600 px) и превью (320 px) в R2.
// Вещь: items/<id>/photo.jpg; место (фото самой коробки): places/<id>/photo.jpg.
// Доступ: только тот, кто может редактировать место (place_role = 'edit').
import { json, presign, userClient, UUID } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const { item_id, place_id } = await req.json().catch(() => ({}));
  const sb = userClient(req);

  let placeId: string, prefix: string;
  if (typeof item_id === "string" && UUID.test(item_id)) {
    const { data: item, error } = await sb.from("items").select("id, place_id").eq("id", item_id).is("deleted_at", null).single();
    if (error || !item) return json({ error: "not_found" }, 404);
    placeId = item.place_id; prefix = `items/${item_id.toLowerCase()}`;
  } else if (typeof place_id === "string" && UUID.test(place_id)) {
    const { data: place, error } = await sb.from("places").select("id").eq("id", place_id).is("deleted_at", null).single();
    if (error || !place) return json({ error: "not_found" }, 404);
    placeId = place_id; prefix = `places/${place_id.toLowerCase()}`;
  } else return json({ error: "id" }, 400);

  const { data: role } = await sb.rpc("place_role", { p_place: placeId });
  if (role !== "edit") return json({ error: "forbidden" }, 403);

  const photoKey = `${prefix}/photo.jpg`;
  const thumbKey = `${prefix}/thumb.jpg`;
  return json({
    photo_key: photoKey,
    photo_url: await presign(photoKey, "PUT", 900),
    thumb_key: thumbKey,
    thumb_url: await presign(thumbKey, "PUT", 900),
  });
});
