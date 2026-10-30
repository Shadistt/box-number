// POST { op: "put" }            → подписанная PUT-ссылка на свой аватар avatars/<uid>.jpg (15 мин) + ключ.
// POST { op: "get", key }       → подписанная GET-ссылка на аватар (1 час). Ключ берётся из profiles.avatar,
//                                  т.е. виден тому, кто видит профиль (сам, семья).
import { json, presign, userClient, UUID } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const body = await req.json().catch(() => ({}));
  const sb = userClient(req);
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  if (body.op === "put") {
    const key = `avatars/${user.id.toLowerCase()}.jpg`;
    return json({ key, url: await presign(key, "PUT", 900) });
  }
  if (body.op === "get") {
    const m = typeof body.key === "string" ? body.key.match(/^avatars\/([0-9a-f-]{36})\.jpg$/) : null;
    if (!m || !UUID.test(m[1])) return json({ error: "key" }, 400);
    if (m[1].toLowerCase() !== user.id.toLowerCase()) {
      const { data } = await sb.from("profiles").select("id").eq("id", m[1]).eq("avatar", body.key).maybeSingle();
      if (!data) return json({ error: "not_found" }, 404);
    }
    return json({ url: await presign(body.key, "GET", 3600) });
  }
  return json({ error: "op" }, 400);
});
