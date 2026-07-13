#!/usr/bin/env python3
"""
score.py — heurística de priorização de programa (importável por discover.py).

Princípio: densidade de bug = taxa de mudança do alvo / nº de olhos em cima.
Gastamos recon pesado só onde o score justifica.

    score = freshness   * W_FRESHNESS
          + scope_size  * W_SCOPE
          + payout_p50  * W_PAYOUT
          - age_program * W_AGE
          - competition * W_COMPETITION

Cada termo é normalizado 0–1 antes de pesar, então o score é comparável
entre plataformas. Ajuste os pesos/constantes abaixo — é o único lugar.

CLI (debug):
    bin/score.py < state/catalog.json     # re-scoreia e imprime tabela
"""
import json
import sys
from datetime import datetime, timezone

# --- pesos (ajustáveis) -----------------------------------------------------
W_FRESHNESS = 3.0
W_SCOPE = 2.0
W_PAYOUT = 2.0
W_AGE = 1.0
W_COMPETITION = 2.0

# --- constantes de normalização ---------------------------------------------
WILDCARD_WEIGHT = 5          # *.x.com pesa muito mais que domínio fixo
DOMAIN_WEIGHT = 1
FRESHNESS_WINDOW_DAYS = 30   # mudança de escopo mais nova que isso = fresca
SCOPE_SIZE_CAP = 50          # satura a contagem ponderada de ativos
PAYOUT_CAP = 10000.0         # USD; satura o payout
AGE_WINDOW_DAYS = 180        # quanto tempo até "já foi peneirado"

# payout p50 de referência por plataforma (USD) quando não há dado
PAYOUT_FALLBACK = {"h1": 500.0, "bugcrowd": 500.0, "intigriti": 450.0}
# competição de referência por plataforma (0–1, maior = mais caçado)
COMPETITION_FALLBACK = {"h1": 0.60, "bugcrowd": 0.50, "intigriti": 0.40}

EUR_TO_USD = 1.08


def _clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def _parse_iso(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def _days_since(iso, now):
    dt = _parse_iso(iso)
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return max(0.0, (now - dt).total_seconds() / 86400.0)


def weighted_scope_size(p):
    """Contagem de ativos in-scope com wildcard pesando WILDCARD_WEIGHT."""
    wilds = set(p.get("wildcards") or [])
    total = 0
    for asset in p.get("scope_in") or []:
        total += WILDCARD_WEIGHT if asset in wilds or "*" in asset else DOMAIN_WEIGHT
    return total


def freshness(p, now):
    """1.0 se o escopo mudou agora, decaindo a 0 em FRESHNESS_WINDOW_DAYS."""
    d = _days_since(p.get("last_scope_change"), now)
    if d is None:
        return 0.5  # sem dado: neutro
    return _clamp(1.0 - d / FRESHNESS_WINDOW_DAYS)


def scope_size_norm(p):
    return _clamp(weighted_scope_size(p) / SCOPE_SIZE_CAP)


def payout_norm(p):
    payout = p.get("max_payout")
    if not payout or payout <= 0:
        payout = PAYOUT_FALLBACK.get(p.get("platform"), 300.0)
    return _clamp(payout / PAYOUT_CAP)


def age_norm(p, now):
    """Proxy de 'já foi peneirado': quanto tempo o programa é conhecido.
    Sem data de início confiável no dataset, usamos first_seen (quando o lab
    o viu pela 1ª vez) — cresce até saturar em AGE_WINDOW_DAYS."""
    d = _days_since(p.get("first_seen"), now)
    if d is None:
        return 0.0
    return _clamp(d / AGE_WINDOW_DAYS)


def competition_norm(p):
    comp = COMPETITION_FALLBACK.get(p.get("platform"), 0.5)
    if p.get("managed"):
        comp = _clamp(comp + 0.1)  # programa gerido = mais olhos
    return _clamp(comp)


def score_program(p, now=None):
    now = now or datetime.now(timezone.utc)
    s = (
        freshness(p, now) * W_FRESHNESS
        + scope_size_norm(p) * W_SCOPE
        + payout_norm(p) * W_PAYOUT
        - age_norm(p, now) * W_AGE
        - competition_norm(p) * W_COMPETITION
    )
    return round(s, 4)


def rank(programs, now=None):
    """Recebe dict {handle: program}, grava 'score' em cada e devolve
    lista de (handle, score) ordenada desc."""
    now = now or datetime.now(timezone.utc)
    scored = []
    for handle, p in programs.items():
        p["score"] = score_program(p, now)
        scored.append((handle, p["score"]))
    scored.sort(key=lambda kv: kv[1], reverse=True)
    return scored


def main():
    stored = "--stored" in sys.argv[1:]
    data = json.load(sys.stdin)
    programs = data.get("programs", data)
    if stored:
        order = sorted(programs.items(), key=lambda kv: kv[1].get("score", 0.0),
                       reverse=True)
        order = [(h, p.get("score", 0.0)) for h, p in order]
    else:
        order = rank(programs)
    print(f"{'':1} {'score':>7}  {'plat':<9} {'ativos':>6}  handle")
    for handle, sc in order:
        p = programs[handle]
        flag = "*" if p.get("tier_eligible") else " "
        n = len(p.get("scope_in") or [])
        print(f"{flag} {sc:7.3f}  {p.get('platform',''):<9} {n:6d}  {handle}")


if __name__ == "__main__":
    main()
