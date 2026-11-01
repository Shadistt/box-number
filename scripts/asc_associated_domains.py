"""Включает capability Associated Domains у App ID co.boxnumber.app (нужно для universal links boxnumber.co/b/<код>).
Идемпотентно: если уже включено — ничего не делает."""
import os, time, json, urllib.request, urllib.error, jwt

KEY_ID, ISSUER, P8 = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_P8"]
BUNDLE = os.environ.get("BUNDLE_ID", "co.boxnumber.app")
BASE = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID})
H = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

def req(method, path, body=None):
    r = urllib.request.Request(BASE + path, headers=H, method=method, data=json.dumps(body).encode() if body else None)
    try:
        with urllib.request.urlopen(r) as resp: return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

st, data = req("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&include=bundleIdCapabilities")
ids = [b for b in data.get("data", []) if b["attributes"]["identifier"] == BUNDLE]
if not ids: raise SystemExit(f"bundle id {BUNDLE} not found: {st} {data}")
bid = ids[0]["id"]
caps = [c["attributes"]["capabilityType"] for c in data.get("included", []) if c["type"] == "bundleIdCapabilities"]
print("bundleId", bid, "capabilities:", caps)
if "ASSOCIATED_DOMAINS" in caps:
    print("ASSOCIATED_DOMAINS already enabled"); raise SystemExit(0)
st, data = req("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "ASSOCIATED_DOMAINS"},
    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
print("enable ASSOCIATED_DOMAINS:", st, json.dumps(data)[:400])
if st >= 300: raise SystemExit(1)
