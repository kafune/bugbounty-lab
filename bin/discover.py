#!/usr/bin/env python3
"""
discover.py — camada de descoberta multi-plataforma.

Baixa o catálogo público de programas (arkadiyt/bounty-targets-data), mescla
com os programas privados que o h1sync.py já materializou, normaliza tudo num
modelo único, ranqueia por score (bin/score.py) e detecta dois sinais de alto
valor comparando com a run anterior:

  NEW_PROGRAM     — handle que não existia na última run.
  SCOPE_EXPANDED  — handle cujo conjunto in-scope cresceu.

Persiste state/catalog.json e rotaciona o anterior pra state/catalog.prev.json.
Dispara bin/notify.sh no delta (a menos de --dry-run).

Uso:
  bin/discover.py                       # todos os 3, notifica
  bin/discover.py --dry-run             # não notifica, só imprime
  bin/discover.py --platforms h1,bugcrowd
  bin/discover.py --min-score 1.5

Config (via .env / ambiente):
  BOUNTY_TARGETS_RAW   base raw do bounty-targets-data
  DISCOVER_PLATFORMS   default de plataformas
  TOP_N                quantos marcar tier_eligible (default 15)
  SCORE_MIN            corte mínimo de score p/ tier_eligible
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Faltou dependência: pip install requests")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import score as scorelib  # noqa: E402
from scope_writer import write_scope  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "state"
TARGETS = ROOT / "targets"
NOTIFY = ROOT / "bin" / "notify.sh"

DEFAULT_RAW = "https://raw.githubusercontent.com/arkadiyt/bounty-targets-data/main/data"
PLATFORM_FILES = {
    "h1": "hackerone_data.json",
    "bugcrowd": "bugcrowd_data.json",
    "intigriti": "intigriti_data.json",
}

# asset types que valem pro pipeline de recon web, por plataforma.
WEB_TYPES = {
    "h1": {"url", "wildcard", "cidr", "ip_address", "domain"},
    "bugcrowd": {"website", "api"},
    "intigriti": {"url"},
}


# ---------------------------------------------------------------------------
# download
# ---------------------------------------------------------------------------
def fetch_json(base, fname):
    url = f"{base.rstrip('/')}/{fname}"
    r = requests.get(url, headers={"Accept": "application/json"}, timeout=90)
    r.raise_for_status()
    return r.json()


# ---------------------------------------------------------------------------
# normalização
# ---------------------------------------------------------------------------
def _scope_hash(assets):
    joined = "\n".join(sorted(set(assets)))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def _split_wildcards(assets):
    return [a for a in assets if "*" in a]


def _slug_from_url(url):
    seg = [s for s in (url or "").rstrip("/").split("/") if s]
    return seg[-1] if seg else ""


def _base_program(platform, url, in_scope, out_scope, private, pays, **extra):
    in_scope = sorted({a.strip() for a in in_scope if a and a.strip()})
    out_scope = sorted({a.strip() for a in out_scope if a and a.strip()})
    prog = {
        "platform": platform,
        "url": url,
        "private": private,
        "pays_bounty": pays,
        "scope_in": in_scope,
        "scope_out": out_scope,
        "wildcards": _split_wildcards(in_scope),
        "scope_hash": _scope_hash(in_scope),
        "score": 0.0,
        "tier_eligible": False,
        "first_seen": None,          # preenchido no merge com a run anterior
        "last_scope_change": None,
    }
    prog.update(extra)              # max_payout, managed, etc.
    return prog


def normalize_h1(entry):
    handle = (entry.get("handle") or "").strip()
    if not handle:
        return None, None
    tgt = entry.get("targets") or {}
    web = WEB_TYPES["h1"]
    ins = [t.get("asset_identifier", "") for t in tgt.get("in_scope", [])
           if (t.get("asset_type") or "").lower() in web]
    out = [t.get("asset_identifier", "") for t in tgt.get("out_of_scope", [])
           if (t.get("asset_type") or "").lower() in web]
    p = _base_program(
        "h1", entry.get("url", f"https://hackerone.com/{handle}"),
        ins, out, private=False, pays=bool(entry.get("offers_bounties")),
        max_payout=None, managed=bool(entry.get("managed_program")),
    )
    return handle, p


def normalize_bugcrowd(entry):
    url = entry.get("url", "")
    handle = _slug_from_url(url)
    if not handle:
        return None, None
    tgt = entry.get("targets") or {}
    web = WEB_TYPES["bugcrowd"]
    ins = [t.get("target", "") for t in tgt.get("in_scope", [])
           if (t.get("type") or "").lower() in web]
    out = [t.get("target", "") for t in tgt.get("out_of_scope", [])
           if (t.get("type") or "").lower() in web]
    payout = entry.get("max_payout")
    p = _base_program(
        "bugcrowd", url, ins, out, private=False,
        pays=bool(payout and payout > 0),
        max_payout=float(payout) if payout else None,
        managed=bool(entry.get("managed_by_bugcrowd")),
    )
    return handle, p


def normalize_intigriti(entry):
    handle = (entry.get("handle") or entry.get("company_handle") or "").strip()
    if not handle:
        return None, None
    tgt = entry.get("targets") or {}
    web = WEB_TYPES["intigriti"]
    ins = [t.get("endpoint", "") for t in tgt.get("in_scope", [])
           if (t.get("type") or "").lower() in web]
    out = [t.get("endpoint", "") for t in tgt.get("out_of_scope", [])
           if (t.get("type") or "").lower() in web]
    mb = entry.get("max_bounty") or {}
    val = mb.get("value")
    if val and (mb.get("currency") or "").upper() == "EUR":
        val = val * scorelib.EUR_TO_USD
    p = _base_program(
        "intigriti", entry.get("url", ""), ins, out, private=False,
        pays=bool(val and val > 0),
        max_payout=float(val) if val else None, managed=False,
    )
    return handle, p


NORMALIZERS = {
    "h1": normalize_h1,
    "bugcrowd": normalize_bugcrowd,
    "intigriti": normalize_intigriti,
}


def _add(catalog, handle, prog):
    """Insere com desambiguação de colisão entre plataformas."""
    key = handle
    if key in catalog and catalog[key]["platform"] != prog["platform"]:
        key = f"{handle}--{prog['platform']}"
    catalog[key] = prog


def merge_private_h1(catalog):
    """Programas privados/convite que o h1sync já materializou aparecem como
    targets/<handle>/scope.raw.json (lista de structured_scopes). Só entram
    se ainda não estão no feed público (senão são públicos mesmo)."""
    if not TARGETS.exists():
        return
    web = WEB_TYPES["h1"]
    for d in sorted(TARGETS.iterdir()):
        if not d.is_dir() or d.name.startswith("_"):
            continue
        raw = d / "scope.raw.json"
        if not raw.exists() or d.name in catalog:
            continue
        try:
            scopes = json.loads(raw.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        if not isinstance(scopes, list):
            continue
        ins, out, pays = [], [], False
        for s in scopes:
            a = s.get("attributes", {}) if isinstance(s, dict) else {}
            ident = (a.get("asset_identifier") or "").strip()
            if not ident or (a.get("asset_type") or "").lower() not in web:
                continue
            if a.get("eligible_for_bounty"):
                pays = True
            (ins if a.get("eligible_for_submission") else out).append(ident)
        if not ins:
            continue
        p = _base_program(
            "h1", f"https://hackerone.com/{d.name}", ins, out,
            private=True, pays=pays, max_payout=None, managed=False,
        )
        catalog[d.name] = p


# ---------------------------------------------------------------------------
# build + diff
# ---------------------------------------------------------------------------
def build_catalog(base, platforms):
    catalog = {}
    for plat in platforms:
        fname = PLATFORM_FILES.get(plat)
        if not fname:
            print(f"  [warn] plataforma desconhecida: {plat}", file=sys.stderr)
            continue
        try:
            data = fetch_json(base, fname)
        except Exception as e:  # rede/JSON — não derruba as outras plataformas
            print(f"  [warn] falha baixando {plat}: {e}", file=sys.stderr)
            continue
        norm = NORMALIZERS[plat]
        added = 0
        for entry in data:
            handle, prog = norm(entry)
            if handle and prog and prog["scope_in"]:
                _add(catalog, handle, prog)
                added += 1
        print(f"  [{plat}] {added} programas com escopo web")
    merge_private_h1(catalog)
    print(f"  [privados] catálogo total: {len(catalog)} programas")
    return catalog


def carry_dates(catalog, prev, now_iso):
    """Preserva first_seen e ajusta last_scope_change comparando scope_hash."""
    prev_progs = (prev or {}).get("programs", {})
    for handle, p in catalog.items():
        old = prev_progs.get(handle)
        if not old:
            p["first_seen"] = now_iso
            p["last_scope_change"] = now_iso
        else:
            p["first_seen"] = old.get("first_seen") or now_iso
            if old.get("scope_hash") == p["scope_hash"]:
                p["last_scope_change"] = old.get("last_scope_change") or now_iso
            else:
                p["last_scope_change"] = now_iso


def diff_signals(catalog, prev):
    """NEW_PROGRAM: handle inédito. SCOPE_EXPANDED: in-scope cresceu."""
    prev_progs = (prev or {}).get("programs", {})
    new_programs, expanded = [], []
    for handle, p in catalog.items():
        old = prev_progs.get(handle)
        if old is None:
            new_programs.append(handle)
            continue
        old_set = set(old.get("scope_in") or [])
        new_set = set(p.get("scope_in") or [])
        added = sorted(new_set - old_set)
        if added:
            expanded.append((handle, added))
    return new_programs, expanded


# ---------------------------------------------------------------------------
# scoring + tier
# ---------------------------------------------------------------------------
def _effective(handle, base):
    """score + boost (Fase D), com fallback pro base se não houver estado."""
    try:
        import state as statelib
        return statelib.effective_score(handle, base)
    except Exception:
        return base


def apply_scores(catalog, top_n, score_min):
    now = datetime.now(timezone.utc)
    scorelib.rank(catalog, now)  # grava p['score'] base em cada programa
    # ordena e corta o top-N pelo score EFETIVO (base + boost do feedback loop):
    # programa que dá bug sobe; programa morto cai e sai do top-N sozinho.
    order = sorted(
        catalog.keys(),
        key=lambda h: _effective(h, catalog[h]["score"]),
        reverse=True,
    )
    eligible = 0
    ranked = []
    for handle in order:
        p = catalog[handle]
        eff = _effective(handle, p["score"])
        if eligible < top_n and eff >= score_min:
            p["tier_eligible"] = True
            eligible += 1
        else:
            p["tier_eligible"] = False
        ranked.append((handle, p["score"]))
    return ranked


# ---------------------------------------------------------------------------
# materialização pro pipeline existente (recon.sh/monitor.sh consomem sem mudar)
# ---------------------------------------------------------------------------
def materialize(catalog):
    """tier_eligible viram targets/<handle>/scope.txt via o writer compartilhado.
    NUNCA sobrescreve um dir gerido pelo h1sync/manual (tem scope.raw.json e
    não carrega nosso marcador .discovered)."""
    n = 0
    for handle, p in catalog.items():
        if not p.get("tier_eligible"):
            continue
        d = TARGETS / handle
        if d.exists() and not (d / ".discovered").exists() \
           and (d / "scope.raw.json").exists():
            print(f"  [skip] {handle}: dir gerido externamente, não sobrescrevo")
            continue
        marker = json.dumps({
            "platform": p["platform"], "score": p["score"],
            "url": p["url"], "private": p["private"],
        })
        write_scope(handle, p["scope_in"], p["scope_out"],
                    raw=None, root=TARGETS, marker=marker)
        n += 1
    return n


# ---------------------------------------------------------------------------
# notify
# ---------------------------------------------------------------------------
def notify(new_programs, expanded, catalog):
    if not new_programs and not expanded:
        return
    lines = ["[bugbounty-lab] discovery"]
    for h in new_programs[:20]:
        p = catalog[h]
        lines.append(f"NEW_PROGRAM {p['platform']}:{h} score={p['score']:.2f} "
                     f"({len(p['scope_in'])} ativos)")
    if len(new_programs) > 20:
        lines.append(f"  … +{len(new_programs) - 20} novos")
    for h, added in expanded[:20]:
        lines.append(f"SCOPE_EXPANDED {catalog[h]['platform']}:{h} +{len(added)} ativo(s)")
    if len(expanded) > 20:
        lines.append(f"  … +{len(expanded) - 20} expandidos")
    msg = "\n".join(lines)
    if NOTIFY.exists():
        subprocess.run(["bash", str(NOTIFY), msg], check=False)
    else:
        print(msg)


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Discovery multi-plataforma")
    ap.add_argument("--platforms", help="csv de plataformas (default do .env)")
    ap.add_argument("--dry-run", action="store_true", help="não notifica, só imprime")
    ap.add_argument("--min-score", type=float, default=None)
    args = ap.parse_args()

    base = os.getenv("BOUNTY_TARGETS_RAW", DEFAULT_RAW)
    plats = (args.platforms or os.getenv("DISCOVER_PLATFORMS", "h1,bugcrowd,intigriti"))
    platforms = [x.strip() for x in plats.split(",") if x.strip()]
    top_n = int(os.getenv("TOP_N", "15"))
    score_min = args.min_score if args.min_score is not None \
        else float(os.getenv("SCORE_MIN", "0.0"))

    STATE.mkdir(parents=True, exist_ok=True)
    cat_path = STATE / "catalog.json"
    prev_path = STATE / "catalog.prev.json"

    prev = None
    if cat_path.exists():
        try:
            prev = json.loads(cat_path.read_text(encoding="utf-8"))
        except ValueError:
            prev = None

    now_iso = datetime.now(timezone.utc).isoformat()
    print("Baixando catálogo…")
    catalog = build_catalog(base, platforms)
    if not catalog:
        sys.exit("Nenhum programa obtido — verifique rede/plataformas.")

    carry_dates(catalog, prev, now_iso)
    order = apply_scores(catalog, top_n, score_min)
    new_programs, expanded = diff_signals(catalog, prev)

    out = {"generated_at": now_iso, "programs": catalog}

    print(f"\nSinais: {len(new_programs)} NEW_PROGRAM, {len(expanded)} SCOPE_EXPANDED")
    print(f"Top {min(top_n, len(order))} (tier_eligible):")
    for handle, sc in order[:top_n]:
        p = catalog[handle]
        flag = "*" if p["tier_eligible"] else " "
        print(f"  {flag} {sc:6.3f}  {p['platform']:<9} {handle}")

    if args.dry_run:
        print("\n[dry-run] catálogo NÃO gravado, notificação NÃO enviada.")
        return

    if prev is not None:
        prev_path.write_text(json.dumps(prev, indent=2), encoding="utf-8")
    cat_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"\nCatálogo gravado: {cat_path.relative_to(ROOT)}")

    materialized = materialize(catalog)
    print(f"Materializados {materialized} programa(s) tier_eligible em targets/")

    notify(new_programs, expanded, catalog)


if __name__ == "__main__":
    main()
