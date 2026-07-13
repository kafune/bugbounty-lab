#!/usr/bin/env python3
"""
findings.py — tracker de achados entre programas.

Cada achado é um markdown em findings/<handle>/<slug>.md com frontmatter
(status, severity, cwe, asset, bounty, h1_report_id...). O corpo é o report H1.

Uso:
  bin/findings.py new <handle> <slug>     # cria do template templates/report/h1-report.md
  bin/findings.py list [handle]           # lista achados (todos ou de um programa)
  bin/findings.py summary                 # dashboard: contagem por status + bounty somado
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FINDINGS = ROOT / "findings"
TEMPLATE = ROOT / "templates" / "report" / "h1-report.md"

STATUSES = ["triaging", "confirmed", "reported", "dup", "negative", "paid"]


def parse_frontmatter(text):
    """Parser mínimo de frontmatter YAML-ish (key: value). Sem dependência externa."""
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    fm = {}
    if not m:
        return fm
    for line in m.group(1).splitlines():
        line = line.split("#", 1)[0].rstrip()  # remove comentário inline
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm


def iter_findings(handle=None):
    base = FINDINGS / handle if handle else FINDINGS
    if not base.exists():
        return
    for md in sorted(base.rglob("*.md")):
        if md.name.startswith("_"):
            continue
        fm = parse_frontmatter(md.read_text(encoding="utf-8", errors="replace"))
        fm["_path"] = md
        fm["_handle"] = md.parent.name
        yield fm


def cmd_new(handle, slug):
    if not TEMPLATE.exists():
        sys.exit(f"template ausente: {TEMPLATE}")
    slug = re.sub(r"[^a-z0-9-]+", "-", slug.lower()).strip("-")
    dest = FINDINGS / handle / f"{slug}.md"
    if dest.exists():
        sys.exit(f"já existe: {dest}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    body = TEMPLATE.read_text(encoding="utf-8")
    body = body.replace('handle: ""', f'handle: "{handle}"')
    dest.write_text(body, encoding="utf-8")
    print(f"criado: {dest.relative_to(ROOT)}")

    # feedback: programa que dá bug sobe no ranking e é revisitado mais.
    try:
        sys.path.insert(0, str(ROOT / "bin"))
        import state as statelib
        statelib.record_finding(handle)
        print(f"  boost de finding aplicado a state/{handle}.json")
    except Exception:
        pass


def cmd_list(handle=None):
    rows = list(iter_findings(handle))
    if not rows:
        print("(nenhum achado)")
        return
    for fm in rows:
        sev = fm.get("severity") or "-"
        st = fm.get("status") or "?"
        title = fm.get("title") or fm["_path"].stem
        print(f"  [{st:9}] {sev:8} {fm['_handle']}/{fm['_path'].stem}  — {title}")


def cmd_summary():
    rows = list(iter_findings())
    if not rows:
        print("(nenhum achado ainda — bin/findings.py new <handle> <slug>)")
        return
    by_status = {s: 0 for s in STATUSES}
    other, bounty = 0, 0.0
    for fm in rows:
        st = fm.get("status", "")
        if st in by_status:
            by_status[st] += 1
        else:
            other += 1
        try:
            bounty += float(fm.get("bounty") or 0)
        except ValueError:
            pass

    print(f"Achados: {len(rows)}  |  bounty acumulado: ${bounty:,.0f}\n")
    for s in STATUSES:
        print(f"  {s:9} {by_status[s]}")
    if other:
        print(f"  {'(outro)':9} {other}")

    fila_report = by_status["confirmed"]
    fila_bounty = by_status["reported"]
    if fila_report:
        print(f"\n  -> {fila_report} confirmado(s) aguardando REPORT")
    if fila_bounty:
        print(f"  -> {fila_bounty} reportado(s) aguardando bounty")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    cmd = args[0]
    if cmd == "new" and len(args) == 3:
        cmd_new(args[1], args[2])
    elif cmd == "list":
        cmd_list(args[1] if len(args) > 1 else None)
    elif cmd == "summary":
        cmd_summary()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
