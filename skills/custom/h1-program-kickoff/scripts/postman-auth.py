#!/usr/bin/env python3
"""Phase 2 — parse a provided Postman collection: dump variables/endpoints, decode any baked
token, and (if it ships a JWT-bearer service account + private key) mint a fresh access token.

This is the single biggest force-multiplier when a program provides one. Generic best-effort:
it recognises the common `service_account` + `tenant` + `secret_key` + token-endpoint pattern.

Usage:
  H1USER=you python3 postman-auth.py "Some_Collection.postman_collection.json"
  H1USER=you python3 postman-auth.py coll.json --mint        # also POST the token endpoint

Requires PyJWT for --mint on RS256/HS256.  pip install pyjwt cryptography
"""
import json, sys, time, base64, ssl, urllib.request, urllib.parse, re

def b64d(s):
    s += "=" * (-len(s) % 4); return base64.urlsafe_b64decode(s)

def decode_jwt(t):
    try:
        h, p = t.split(".")[:2]
        return json.loads(b64d(h)), json.loads(b64d(p))
    except Exception:
        return None, None

def walk(items, path=""):
    for it in items:
        if "item" in it:
            yield from walk(it["item"], path + "/" + it.get("name",""))
        else:
            yield path, it

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    coll = json.load(open(sys.argv[1]))
    mint = "--mint" in sys.argv
    V = {v["key"]: v.get("value") for v in coll.get("variable", [])}

    print("== collection:", coll.get("info", {}).get("name"))
    print("== variables ==")
    for k, v in V.items():
        sv = (v or "")
        if any(x in k.lower() for x in ("secret", "key", "token", "password")):
            sv = (sv[:24] + "…(%d chars)" % len(sv)) if sv else ""
        print(f"   {k:20} = {str(sv)[:70]}")

    # decode any baked token
    for k, v in V.items():
        if v and isinstance(v, str) and v.count(".") == 2 and v.startswith("eyJ"):
            h, p = decode_jwt(v)
            if p:
                exp = p.get("exp"); now = int(time.time())
                print(f"\n== baked token '{k}' claims ==")
                for kk in ("iss","aud","aud_hr","sub","clid","scope","tenant"):
                    if kk in p: print(f"   {kk}: {str(p[kk])[:80]}")
                if exp: print(f"   exp: {exp} ({'EXPIRED' if exp<now else 'valid'}; now={now})")

    print("\n== endpoints ==")
    token_url = None
    for path, it in walk(coll.get("item", [])):
        req = it.get("request", {}); m = req.get("method","")
        url = req.get("url", {}); raw = url.get("raw") if isinstance(url, dict) else url
        print(f"   {m:5} {it.get('name','')[:24]:24} {raw}")
        if raw and "token" in (raw or "") and m == "POST":
            token_url = raw
        # surface the auth-building pre-request script (shows exact claim construction)
        for ev in it.get("event", []):
            if ev.get("listen") == "prerequest":
                body = "\n".join(ev["script"]["exec"])
                if "sign" in body or "jwt" in body.lower() or "assertion" in body.lower():
                    print("     (this request has a JWT-building pre-request script — inspect for claim shape)")

    if not mint:
        print("\nRe-run with --mint to attempt token minting (needs PyJWT).")
        return

    # --- mint: recognise service_account + tenant + secret_key (RS256 JWT-bearer) ---
    sa  = V.get("service_account"); tenant = V.get("tenant"); pk = V.get("secret_key")
    if not (sa and tenant and pk and token_url):
        print("\n[!] could not auto-detect the (service_account, tenant, secret_key, token_url) pattern.")
        print("    Inspect the JWT request's pre-request script and craft the assertion manually.")
        return
    import jwt
    payload = {
        "iss": f"{sa}@{tenant}.iam.acesso.io",   # <-- adjust iss format to the program's pre-request script
        "aud": re.sub(r"/oauth2/token.*$", "", token_url),
        "scope": "*", "iat": int(time.time()), "exp": int(time.time()) + 3600,
    }
    print("\n== assertion payload (adjust iss/aud to match the collection's script) ==")
    print("  ", json.dumps(payload))
    assertion = jwt.encode(payload, pk, algorithm="RS256", headers={"typ": "JWT"})
    data = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion,
    }).encode()
    ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
    import os
    req = urllib.request.Request(token_url, data=data, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": os.environ.get("BUA","Mozilla/5.0 Chrome/126"),
        "X-HackerOne-Research": os.environ.get("H1USER","research"),
    })
    try:
        r = urllib.request.urlopen(req, context=ctx, timeout=20)
        out = json.loads(r.read()); at = out.get("access_token")
        print("\n[+] access_token minted:", "yes" if at else "no", "| expires_in:", out.get("expires_in"))
        if at:
            _, claims = decode_jwt(at)
            print("    claims:", json.dumps({k: claims.get(k) for k in ("aud","aud_hr","sub","clid","scope")})[:300])
            open("token.txt","w").write(at); print("    saved -> token.txt")
    except urllib.error.HTTPError as e:
        print("[!] token endpoint:", e.code, e.read().decode()[:300])

if __name__ == "__main__":
    main()
