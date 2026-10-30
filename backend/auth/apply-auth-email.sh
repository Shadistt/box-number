#!/bin/sh
# Включает Resend как SMTP для Supabase Auth и применяет русские шаблоны писем.
# Использование: SUPABASE_ACCESS_TOKEN=sbp_… RESEND_API_KEY=re_… ./apply-auth-email.sh
set -e
REF=zolpdtkhfndravxisuzs
cd "$(dirname "$0")"
python3 - <<PY
import json, os, subprocess
tpl = json.load(open("email-templates.json")); tpl.pop("_comment", None)
cfg = {
  "external_email_enabled": True,
  "mailer_autoconfirm": False,
  "mailer_secure_email_change_enabled": True,
  "smtp_host": "smtp.resend.com",
  "smtp_port": 465,
  "smtp_user": "resend",
  "smtp_pass": os.environ["RESEND_API_KEY"],
  "smtp_admin_email": "noreply@mail.boxnumber.co",
  "smtp_sender_name": "Box Nº",
  "smtp_max_frequency": 60,
  "rate_limit_email_sent": 60,
  **tpl,
}
r = subprocess.run(["curl","-sS","-X","PATCH",f"https://api.supabase.com/v1/projects/$REF/config/auth",
  "-H",f"Authorization: Bearer {os.environ['SUPABASE_ACCESS_TOKEN']}","-H","Content-Type: application/json","-d",json.dumps(cfg)],capture_output=True,text=True)
d = json.loads(r.stdout)
print({k: d.get(k) for k in ["smtp_host","smtp_port","smtp_user","smtp_admin_email","smtp_sender_name","rate_limit_email_sent","mailer_subjects_confirmation"]})
PY
