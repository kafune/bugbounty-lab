#!/usr/bin/env python3
"""
h1sync.py — puxa programas + escopo estruturado da API do HackerOne e
materializa arquivos de escopo por programa em targets/<handle>/.

Auth: HTTP Basic (API username + API token).
Gere o token em: HackerOne > Settings > API Token.
Docs: https://api.hackerone.com/getting-started-hacker-api/

Uso:
  export H1_USER="seu_username"
  export H1_TOKEN="seu_token"
  ./bin/h1sync.py                    # sincroniza todos os programas acessíveis
  ./bin/h1sync.py --handle acme      # só um programa
  ./bin/h1sync.py --only-bounty      # só assets eligible_for_bounty
  ./bin/h1sync.py --types url,wildcard   # filtra por asset_type

Saída por programa (em targets/<handle>/):
  scope.txt          -> assets in-scope (1 por linha, para o recon consumir)
  out-of-scope.txt   -> assets marcados como não-submissíveis
  scope.raw.json     -> resposta bruta da API (fidelidade total)
"""
import argparse
import os
import sys
import time
from pathlib import Path
from urllib.parse import urlencode

try:
    import requests
except ImportError:
    sys.exit("Faltou dependência: pip install requests")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scope_writer import write_scope  # writer de escopo compartilhado

BASE = "https://api.hackerone.com/v1/hackers"
ROOT = Path(__file__).resolve().parent.parent
TARGETS = ROOT / "targets"

# asset_type que faz sentido jogar no pipeline de recon web.
WEB_TYPES = {"url", "wildcard", "cidr", "ip_address", "domain"}


def auth():
    user, token = os.getenv("H1_USER"), os.getenv("H1_TOKEN")
    if not user or not token:
        sys.exit("Defina H1_USER e H1_TOKEN no ambiente (veja .env.example).")
    return (user, token)


def get_paginated(path, creds, params=None):
    """Itera todas as páginas seguindo links.next."""
    params = dict(params or {})
    params.setdefault("page[size]", 100)
    url = f"{BASE}{path}?{urlencode(params)}"
    out = []
    while url:
        r = requests.get(url, auth=creds, headers={"Accept": "application/json"}, timeout=30)
        if r.status_code == 401:
            sys.exit("401 — credenciais inválidas. Confira H1_USER / H1_TOKEN.")
        if r.status_code == 429:
            wait = int(r.headers.get("Retry-After", 5))
            time.sleep(wait)
            continue
        r.raise_for_status()
        body = r.json()
        out.extend(body.get("data", []))
        url = body.get("links", {}).get("next")
    return out


def list_programs(creds):
    return [p["attributes"]["handle"] for p in get_paginated("/programs", creds)]


def get_scopes(handle, creds):
    return get_paginated(f"/programs/{handle}/structured_scopes", creds)


def sync_program(handle, creds, only_bounty=False, types=None):
    scopes = get_scopes(handle, creds)
    if not scopes:
        print(f"  [{handle}] sem structured_scopes acessíveis")
        return

    types = types or WEB_TYPES
    in_scope, out_scope = [], []
    for s in scopes:
        a = s["attributes"]
        ident = a.get("asset_identifier", "").strip()
        if not ident:
            continue
        if a.get("asset_type", "").lower() not in types:
            continue
        if only_bounty and not a.get("eligible_for_bounty"):
            continue
        (in_scope if a.get("eligible_for_submission") else out_scope).append(ident)

    write_scope(handle, in_scope, out_scope, raw=scopes)
    print(f"  [{handle}] in-scope={len(set(in_scope))}  out={len(set(out_scope))}")


def main():
    ap = argparse.ArgumentParser(description="Sincroniza escopo do HackerOne")
    ap.add_argument("--handle", help="sincroniza só este programa")
    ap.add_argument("--only-bounty", action="store_true", help="só assets eligible_for_bounty")
    ap.add_argument("--types", help="asset_types separados por vírgula (default: web)")
    args = ap.parse_args()

    creds = auth()
    types = set(args.types.lower().split(",")) if args.types else None

    if args.handle:
        handles = [args.handle]
    else:
        print("Listando programas acessíveis...")
        handles = list_programs(creds)
        print(f"{len(handles)} programas encontrados.")

    for h in handles:
        sync_program(h, creds, only_bounty=args.only_bounty, types=types)

    print(f"\nEscopo materializado em: {TARGETS}/")


if __name__ == "__main__":
    main()
