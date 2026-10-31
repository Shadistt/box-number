// POST { email, kind: "family" | "move" | "place", move_id?, place_id?, role?: "view"|"edit" }
// Создаёт приглашение (строка с invited_email; привяжется при входе человека с этим email — claim_invites())
// и шлёт письмо через Resend. Если у человека уже есть аккаунт — даём доступ сразу (user_id), письмо всё равно уходит.
import { createClient } from "npm:@supabase/supabase-js@2";
import { json, userClient } from "../_shared/r2.ts";

const FROM = Deno.env.get("SUPPORT_FROM") ?? "Box Nº <noreply@mail.boxnumber.co>";
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const b = await req.json().catch(() => ({}));
  const email = String(b.email ?? "").trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "email" }, 400);
  const kind = b.kind, role = b.role === "edit" ? "edit" : "view";

  const sb = userClient(req);
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);
  if (email === (user.email ?? "").toLowerCase()) return json({ error: "self" }, 400);

  // Есть ли уже аккаунт с таким email — через сервисный ключ (auth.users недоступна пользователю).
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: existing } = await admin.from("profiles").select("id, first_name").eq("email", email).maybeSingle();
  const target = existing ? { user_id: existing.id, status: "active" } : { invited_email: email, status: "invited" };

  const { data: me } = await sb.from("profiles").select("first_name, last_name").eq("id", user.id).single();
  const inviter = [me?.first_name, me?.last_name].filter(Boolean).join(" ") || user.email;
  let what = "", err: string | null = null;

  if (kind === "family") {
    const { data: fid } = await sb.rpc("my_family");
    if (existing) {
      const { data: inFamily } = await admin.from("family_members").select("id").eq("user_id", existing.id).maybeSingle();
      if (inFamily) return json({ error: "in_family" }, 409);
    }
    // on_conflict не ловит повторные приглашения (user_id null) — проверяем email сами, иначе «Напомнить» плодил бы строки
    const { data: dup } = existing ? { data: null } : await sb.from("family_members").select("id").eq("family_id", fid).eq("invited_email", email).maybeSingle();
    if (!dup) {
      const { error } = await sb.from("family_members").upsert({ family_id: fid, role: "edit", ...target }, { onConflict: "user_id", ignoreDuplicates: true });
      err = error?.message ?? null;
    }
    what = "в семью";
  } else if (kind === "move" && typeof b.move_id === "string") {
    const { data: dupM } = existing ? { data: null } : await sb.from("move_access").select("id").eq("move_id", b.move_id).eq("invited_email", email).maybeSingle();
    if (!dupM) {
      const { error } = await sb.from("move_access").upsert({ move_id: b.move_id, role, granted_by: user.id, ...target }, { onConflict: "move_id,user_id" });
      err = error?.message ?? null;
    }
    what = "в переезд";
    // в переезд → заодно в семью, как в ТЗ §9
    const { data: fid } = await sb.rpc("my_family");
    const { data: inFam } = existing
      ? await admin.from("family_members").select("id").eq("user_id", existing.id).maybeSingle()
      : await sb.from("family_members").select("id").eq("family_id", fid).eq("invited_email", email).maybeSingle();
    if (!inFam) await sb.from("family_members").upsert({ family_id: fid, role: "edit", ...target }, { onConflict: "user_id", ignoreDuplicates: true });
  } else if (kind === "place" && typeof b.place_id === "string") {
    const { data: dupP } = existing ? { data: null } : await sb.from("place_access").select("id").eq("place_id", b.place_id).eq("invited_email", email).maybeSingle();
    if (!dupP) {
      const { error } = await sb.from("place_access").upsert({ place_id: b.place_id, role, granted_by: user.id, ...target }, { onConflict: "place_id,user_id" });
      err = error?.message ?? null;
    }
    what = "к месту";
    if (!err) await sb.from("places").update({ shared: true }).eq("id", b.place_id);
  } else return json({ error: "kind" }, 400);
  if (err) { console.error(err); return json({ error: "insert_failed", detail: err }, 400); }

  const key = Deno.env.get("RESEND_API_KEY");
  if (key) {
    const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;padding:32px 20px;color:#16171A">
<p style="font-size:22px;font-weight:800;margin:0 0 8px">Box <span style="color:#F0561D">Nº</span></p>
<h1 style="font-size:20px;margin:24px 0 8px">${esc(inviter)} приглашает вас ${what}</h1>
<p style="font-size:15px;line-height:1.5;color:#4F5157;margin:0 0 20px">Box Nº — коробки с номером маркером и фото всего, что внутри. ${existing ? "Откройте приложение — доступ уже есть." : "Установите приложение и войдите с этим адресом (" + esc(email) + ") — доступ появится сам."}</p>
<p style="margin:0 0 24px"><a href="https://boxnumber.co" style="display:inline-block;background:#16171A;color:#FFFFFF;text-decoration:none;font-weight:600;font-size:15px;padding:14px 22px;border-radius:14px">Открыть Box Nº</a></p>
<p style="font-size:13px;line-height:1.5;color:#8A8C92;margin:0">Если вы не ждали приглашения, просто не обращайте внимания на это письмо.</p></div>`;
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: FROM, to: [email], reply_to: user.email, subject: `${inviter} приглашает вас в Box Nº`, html }),
    });
    if (!res.ok) console.error("resend:", res.status, await res.text());
  }
  return json({ ok: true, existing: !!existing });
});
