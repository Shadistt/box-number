// POST { key } → подписанная ссылка на чтение фото (1 час).
// items/<id>/… — любой, кто видит вещь (RLS на items); places/<id>/… — кто видит место (RLS на places).
import { json, presign, userClient, UUID } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const { key } = await req.json().catch(() => ({}));
  const m = typeof key === "string" ? key.match(/^(items|places)\/([0-9a-f-]{36})\/(photo|thumb)\.jpg$/) : null;
  if (!m || !UUID.test(m[2])) return json({ error: "key" }, 400);

  const sb = userClient(req);
  const { data } = await sb.from(m[1]).select("id").eq("id", m[2]).single();
  if (!data) return json({ error: "not_found" }, 404);

  return json({ url: await presign(key, "GET", 3600) });
});
