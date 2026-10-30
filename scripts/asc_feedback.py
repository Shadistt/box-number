"""Отзывы TestFlight (скриншоты + текст, крэши) через App Store Connect API.
Нужны переменные ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Печатает текст, скриншоты кладёт в feedback/."""
import os, sys, time, json, pathlib, urllib.request, urllib.parse
import jwt  # pyjwt[crypto]

KEY_ID, ISSUER, P8 = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_P8"]
BUNDLE = "co.boxnumber.app"
BASE = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   P8, algorithm="ES256", headers={"kid": KEY_ID})

def get(path, **q):
    url = BASE + path + ("?" + urllib.parse.urlencode(q) if q else "")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as r: return json.load(r)

app = get("/v1/apps", **{"filter[bundleId]": BUNDLE})["data"][0]
app_id = app["id"]
print(f"App {app['attributes']['name']} ({app_id})\n")
out = pathlib.Path("feedback"); out.mkdir(exist_ok=True)

shots = get(f"/v1/apps/{app_id}/betaFeedbackScreenshotSubmissions", **{"include": "tester,build", "limit": 50})
print(f"== Отзывы со скриншотами: {len(shots['data'])}")
for i, s in enumerate(shots["data"], 1):
    a = s["attributes"]
    print(f"\n#{i} {a.get('createdDate')} · build {a.get('buildBundleId','')} · {a.get('deviceModel')} iOS {a.get('osVersion')} · {a.get('locale')}")
    print("   ", (a.get("comment") or "").replace("\n", "\n    "))
    for j, img in enumerate(a.get("screenshots") or [], 1):
        url = img.get("url")
        if url:
            data = urllib.request.urlopen(url).read()
            (out / f"{i}-{j}.png").write_bytes(data)
            print(f"    скриншот: feedback/{i}-{j}.png")

crashes = get(f"/v1/apps/{app_id}/betaFeedbackCrashSubmissions", **{"limit": 50})
print(f"\n== Отчёты о сбоях: {len(crashes['data'])}")
for i, c in enumerate(crashes["data"], 1):
    a = c["attributes"]
    print(f"#{i} {a.get('createdDate')} · {a.get('deviceModel')} iOS {a.get('osVersion')} · {a.get('comment')}")

# ---- сертификаты (чтобы видеть, что накопил CI) ----
certs = get("/v1/certificates", **{"limit": 200})
print(f"\n== Сертификаты: {len(certs['data'])}")
for c in certs["data"]:
    a = c["attributes"]
    print(f"{c['id']} · {a.get('certificateType')} · {a.get('name')} · {a.get('displayName')} · до {a.get('expirationDate','')[:10]}")
