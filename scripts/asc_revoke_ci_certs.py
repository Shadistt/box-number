"""Отзыв сертификатов «Apple Development: Created via API», которые плодили одноразовые сборщики GitHub.
Удаляет только DEVELOPMENT-сертификаты с таким именем и датой окончания не раньше CUTOFF (т.е. созданные в этом проекте)."""
import os, time, json, urllib.request, jwt

KEY_ID, ISSUER, P8 = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_P8"]
CUTOFF = os.environ.get("CUTOFF", "2027-10-29")
BASE = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID})
H = {"Authorization": f"Bearer {token}"}

def req(method, path):
    r = urllib.request.Request(BASE + path, headers=H, method=method)
    with urllib.request.urlopen(r) as resp: return resp.status, resp.read()

_, body = req("GET", "/v1/certificates?limit=200")
for c in json.loads(body)["data"]:
    a = c["attributes"]
    if a.get("certificateType") == "DEVELOPMENT" and a.get("displayName") == "Created via API" and a.get("expirationDate", "")[:10] >= CUTOFF:
        st, _ = req("DELETE", f"/v1/certificates/{c['id']}")
        print("revoked", c["id"], a.get("expirationDate", "")[:10], st)
print("done")
