// POST {} → удаляет аккаунт вызвавшего: файлы в R2 (фото вещей, аватар), затем пользователя Auth
// (profiles/moves/places/items уходят каскадом). Нужен сервисный ключ — он есть в окружении функций
// как SUPABASE_SERVICE_ROLE_KEY; в приложении его нет и быть не должно.
import { createClient } from "npm:@supabase/supabase-js@2";
import { json, userClient, r2Delete } from "../_shared/r2.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const { data: { user } } = await userClient(req).auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // Файлы — до удаления строк, иначе ключи потеряем. Ошибки R2 не блокируют удаление аккаунта.
  const { data: keys } = await admin.rpc("account_object_keys", { p_user: user.id });
  let removed = 0;
  for (const key of (keys ?? []) as string[]) {
    try { await r2Delete(key); removed++; } catch (e) { console.error("r2 delete", key, e); }
  }

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) { console.error("deleteUser:", error); return json({ error: "delete_failed" }, 500); }
  return json({ ok: true, files_removed: removed });
});
