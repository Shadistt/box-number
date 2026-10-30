#!/bin/sh
# Деплой Edge Functions через Management API (без CLI).
# Использование: SUPABASE_ACCESS_TOKEN=sbp_… ./deploy.sh avatar-url support-ticket delete-account
set -e
REF=zolpdtkhfndravxisuzs
cd "$(dirname "$0")"
for fn in "$@"; do
  meta=$(printf '{"name":"%s","entrypoint_path":"%s/index.ts","verify_jwt":true}' "$fn" "$fn")
  out=$(curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/functions/deploy?slug=$fn" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -F "metadata=$meta" \
    -F "file=@$fn/index.ts;filename=$fn/index.ts" \
    -F "file=@_shared/r2.ts;filename=_shared/r2.ts")
  echo "$fn: $(echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status"), "v"+str(d.get("version")), d.get("message",""))')"
done
