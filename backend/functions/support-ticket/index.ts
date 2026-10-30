// POST { subject, message, device?: string, screenshots?: [base64 jpeg, ≤3, ≤1.5 МБ каждый] }
// → письмо в support@boxnumber.co через Resend API, reply_to = email пользователя.
// Секрет: RESEND_API_KEY (ключ только на отправку).
import { json, userClient } from "../_shared/r2.ts";

const TO = Deno.env.get("SUPPORT_TO") ?? "support@boxnumber.co";
const FROM = Deno.env.get("SUPPORT_FROM") ?? "Box Nº <noreply@mail.boxnumber.co>";

function esc(s: string) {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return json({ error: "not_configured" }, 500);

  const sb = userClient(req);
  const { data: { user } } = await sb.auth.getUser();
  if (!user?.email) return json({ error: "unauthorized" }, 401);

  const b = await req.json().catch(() => ({}));
  const subject = String(b.subject ?? "").trim().slice(0, 200);
  const message = String(b.message ?? "").trim().slice(0, 10_000);
  if (!subject || !message) return json({ error: "empty" }, 400);
  const device = typeof b.device === "string" ? b.device.slice(0, 500) : "";
  const shots: string[] = Array.isArray(b.screenshots) ? b.screenshots.slice(0, 3) : [];
  if (shots.some((s) => typeof s !== "string" || s.length > 2_100_000)) return json({ error: "screenshot_too_big" }, 400);

  const { data: profile } = await sb.from("profiles").select("first_name, last_name").eq("id", user.id).maybeSingle();
  const name = [profile?.first_name, profile?.last_name].filter(Boolean).join(" ") || "—";

  const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:640px;color:#16171A">
<p style="white-space:pre-wrap;font-size:15px;line-height:1.5">${esc(message)}</p>
<hr style="border:0;border-top:1px solid #D9D6CF;margin:20px 0">
<p style="font-size:13px;color:#5E6066;margin:0">${esc(name)} · ${esc(user.email)} · id ${user.id}${device ? "<br>" + esc(device) : ""}</p>
</div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: FROM,
      to: [TO],
      reply_to: user.email,
      subject: `[Box Nº] ${subject}`,
      html,
      attachments: shots.map((content, i) => ({ content, filename: `screenshot-${i + 1}.jpg` })),
    }),
  });
  if (!res.ok) {
    console.error("resend:", res.status, await res.text());
    return json({ error: "send_failed" }, 502);
  }
  return json({ ok: true });
});
