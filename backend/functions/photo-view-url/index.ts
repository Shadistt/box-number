// POST { key } → подписанная ссылка на чтение фото (1 час).
// Доступ: любой, кто видит вещь (RLS на items).
import { json, presign, userClient, UUID } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const { key } = await req.json().catch(() => ({}));
  const m = typeof key === "string" ? key.match(/^items\/([0-9a-f-]{36})\/(photo|thumb)\.jpg$/) : null;
  if (!m || !UUID.test(m[1])) return json({ error: "key" }, 400);

  const sb = userClient(req);
  const { data: item } = await sb.from("items").select("id").eq("id", m[1]).single();
  if (!item) return json({ error: "not_found" }, 404);

  return json({ url: await presign(key, "GET", 3600) });
});
