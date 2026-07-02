#!/usr/bin/env python3
"""Phase 4 — reconstruct source from a .map (URL or local file).

Handles the prefixes seen in the wild:
  webpack:///./src/...                (classic)
  webpack://<project-name>/./src/...  (module federation, e.g. webpack://you-payment/...)
  ../../../libs/...                    (monorepo libs)
Keeps app code (src/, libs/), drops node_modules / webpack runtime.

Usage:
  H1USER=you python3 sourcemap.py https://app.example.com/main.js.map  out_dir
  python3 sourcemap.py ./main.js.map  out_dir
"""
import json, os, sys, ssl, urllib.request

def load(src):
    if src.startswith("http"):
        ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
        ua = os.environ.get("BUA","Mozilla/5.0 Chrome/126")
        h = {"User-Agent": ua, "X-HackerOne-Research": os.environ.get("H1USER","research")}
        return json.load(urllib.request.urlopen(urllib.request.Request(src, headers=h), context=ctx, timeout=30))
    return json.load(open(src))

def norm(s):
    # strip "webpack://<anything>/" or "webpack:///"
    if s.startswith("webpack://"):
        s = s[len("webpack://"):]
        s = s.split("/", 1)[1] if "/" in s else s     # drop the project segment
    while s.startswith(("../", "./")):
        s = s[3:] if s.startswith("../") else s[2:]
    return s.lstrip("/")

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    m = load(sys.argv[1]); outdir = sys.argv[2]
    srcs, conts = m.get("sources", []), m.get("sourcesContent")
    if not conts:
        print("[!] no sourcesContent in this map (only mappings) — cannot reconstruct"); sys.exit(2)
    n = skip = 0
    for s, c in zip(srcs, conts):
        if c is None or "/node_modules/" in s or "webpack/runtime" in s:
            skip += 1; continue
        p = norm(s)
        if not p or p.startswith(".."):
            skip += 1; continue
        fp = os.path.join(outdir, p)
        os.makedirs(os.path.dirname(fp) or ".", exist_ok=True)
        open(fp, "w", encoding="utf-8", errors="replace").write(c); n += 1
    print(f"[+] wrote {n} source files to {outdir}/  (skipped {skip} vendor/runtime)")
    # quick hints for where the surface lives
    import subprocess
    try:
        hits = subprocess.run(["grep","-rilE","fetch\\(|axios|baseURL|/api/|/client/|Authorization|interceptor|integrations",outdir],
                              capture_output=True, text=True).stdout.splitlines()
        if hits:
            print("[+] API/auth-relevant files:")
            for h in hits[:25]: print("    ", h)
    except Exception:
        pass

if __name__ == "__main__":
    main()
