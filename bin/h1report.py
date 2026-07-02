#!/usr/bin/env python3
"""
h1report.py — monta (e, com --submit, cria) um report no HackerOne a partir de
um achado findings/<handle>/<slug>.md.

Por segurança, o DEFAULT é DRY-RUN: só imprime o payload que seria enviado.
A submissão real só acontece com --submit explícito. Confira o texto antes.

Auth: HTTP Basic (H1_USER + H1_TOKEN) — mesmo par do h1sync.py.
Docs: https://api.hackerone.com/hacker-resources/#reports-create-report

Uso:
  bin/h1report.py findings/acme/idor-transactions.md            # dry-run (imprime payload)
  bin/h1report.py findings/acme/idor-transactions.md --submit   # cria o report de verdade
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Faltou dependência: pip install requests")

API = "https://api.hackerone.com/v1/hackers/reports"

SEV_MAP = {"none": "none", "low": "low", "medium": "medium",
           "high": "high", "critical": "critical"}


def split_frontmatter(text):
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", text, re.DOTALL)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        line = line.split("#", 1)[0].rstrip()
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm, m.group(2).strip()


def build_payload(fm, body):
    handle = fm.get("handle", "").strip()
    title = fm.get("title", "").strip()
    if not handle or handle == "_EXAMPLE":
        sys.exit("frontmatter 'handle' ausente ou é _EXAMPLE — ajuste antes de submeter.")
    if not title:
        sys.exit("frontmatter 'title' ausente.")
    attrs = {
        "team_handle": handle,
        "title": title,
        "vulnerability_information": body,
    }
    sev = fm.get("severity", "").lower()
    if sev in SEV_MAP and sev != "none":
        attrs["severity_rating"] = SEV_MAP[sev]
    if fm.get("weakness"):
        attrs["_weakness_hint"] = fm["weakness"]  # informativo; weakness_id real precisa de lookup
    return {"data": {"type": "report", "attributes": attrs}}


def main():
    ap = argparse.ArgumentParser(description="Monta/cria report no HackerOne a partir de um findings/*.md")
    ap.add_argument("finding", help="caminho do findings/<handle>/<slug>.md")
    ap.add_argument("--submit", action="store_true", help="CRIA o report (default é dry-run)")
    args = ap.parse_args()

    path = Path(args.finding)
    if not path.exists():
        sys.exit(f"arquivo não encontrado: {path}")
    fm, body = split_frontmatter(path.read_text(encoding="utf-8"))
    payload = build_payload(fm, body)
    payload["data"]["attributes"].pop("_weakness_hint", None)

    if not args.submit:
        print("== DRY-RUN (nada enviado). Payload que SERIA criado ==\n")
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        print("\nConfira o texto e rode de novo com --submit para criar o report.")
        return

    user, token = os.getenv("H1_USER"), os.getenv("H1_TOKEN")
    if not user or not token:
        sys.exit("Defina H1_USER e H1_TOKEN (veja .env.example).")
    r = requests.post(API, auth=(user, token),
                      headers={"Accept": "application/json", "Content-Type": "application/json"},
                      data=json.dumps(payload), timeout=30)
    if r.status_code in (200, 201):
        rid = r.json().get("data", {}).get("id", "?")
        print(f"report criado: id={rid}")
        print(f"anote no frontmatter: h1_report_id: \"{rid}\" e status: reported")
    else:
        print(f"falha HTTP {r.status_code}:\n{r.text}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
