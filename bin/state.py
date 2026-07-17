#!/usr/bin/env python3
"""
state.py — estado por programa + feedback loop. Faz a esteira aprender sozinha
onde tem bug frequente.

Cada programa tem state/<handle>.json (git-ignored):

  {
    "handle": "acme", "score": 0.0, "tier": 1,
    "last_tier1_run": "ISO", "last_tier2_run": "ISO", "last_delta_at": "ISO",
    "consecutive_empty_runs": 0, "boost": 0.0
  }

Feedback:
  - delta não-vazio no monitor  -> boost += (escalado pela contagem), zera empties
  - N runs vazias seguidas       -> boost -= penalidade (decai)
  - finding válido (findings.py) -> boost grande (revisita mais)

O score EFETIVO (score + boost) reordena o top-N no discover e no run-tier.

CLI (pra ser chamado do bash):
  state.py delta   <handle> <count>       registra delta de superfície
  state.py empty   <handle>               registra run sem delta
  state.py finding <handle>               registra achado válido
  state.py tier-run <handle> <1|2>        carimba last_tierN_run
  state.py effective <handle> <base>      imprime score efetivo
  state.py get     <handle>               imprime o json do estado
  state.py rank [--eligible]              imprime handles por score efetivo
"""
import json
import os
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from fcntl import LOCK_EX, LOCK_UN, flock
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path(os.getenv("BBLAB_STATE_DIR", ROOT / "state"))

# --- constantes de feedback (ajustáveis) ------------------------------------
DELTA_BOOST_BASE = 0.4       # por run com delta
DELTA_BOOST_PER_ITEM = 0.02  # + por item novo (satura)
DELTA_BOOST_CAP = 1.5        # teto do ganho de uma única run
FINDING_BOOST = 3.0          # achado válido pesa muito
EMPTY_THRESHOLD = 3          # runs vazias toleradas antes de penalizar
EMPTY_PENALTY = 0.4          # penalidade por run vazia acima do limiar
BOOST_MIN, BOOST_MAX = -5.0, 10.0


def _now():
    return datetime.now(timezone.utc).isoformat()


def _clamp(x, lo, hi):
    return max(lo, min(hi, x))


def path(handle):
    return STATE / f"{handle}.json"


@contextmanager
def locked(handle):
    locks = STATE / "locks"
    locks.mkdir(parents=True, exist_ok=True)
    with (locks / f"{handle}.state.lock").open("a+") as lock:
        flock(lock.fileno(), LOCK_EX)
        try:
            yield
        finally:
            flock(lock.fileno(), LOCK_UN)


def load(handle):
    p = path(handle)
    base = {
        "handle": handle, "score": 0.0, "tier": 1,
        "last_tier1_run": None, "last_tier2_run": None, "last_delta_at": None,
        "consecutive_empty_runs": 0, "boost": 0.0,
    }
    if p.exists():
        try:
            base.update(json.loads(p.read_text(encoding="utf-8")))
        except ValueError:
            pass
    return base


def save(handle, st):
    STATE.mkdir(parents=True, exist_ok=True)
    st["boost"] = round(_clamp(st.get("boost", 0.0), BOOST_MIN, BOOST_MAX), 4)
    target = path(handle)
    fd, temporary = tempfile.mkstemp(prefix=f".{handle}.", suffix=".tmp", dir=STATE)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(st, output, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, target)
    finally:
        try:
            Path(temporary).unlink()
        except FileNotFoundError:
            pass
    return st


def effective_score(handle, base_score):
    """base + boost. Não cria arquivo se não existir (só lê)."""
    try:
        return round(float(base_score) + load(handle).get("boost", 0.0), 4)
    except (TypeError, ValueError):
        return float(base_score or 0.0)


def record_delta(handle, count):
    with locked(handle):
        st = load(handle)
        gain = min(DELTA_BOOST_BASE + DELTA_BOOST_PER_ITEM * max(0, count),
                   DELTA_BOOST_CAP)
        st["boost"] = st.get("boost", 0.0) + gain
        st["consecutive_empty_runs"] = 0
        st["last_delta_at"] = _now()
        return save(handle, st)


def record_empty(handle):
    with locked(handle):
        st = load(handle)
        st["consecutive_empty_runs"] = st.get("consecutive_empty_runs", 0) + 1
        if st["consecutive_empty_runs"] > EMPTY_THRESHOLD:
            st["boost"] = st.get("boost", 0.0) - EMPTY_PENALTY
        return save(handle, st)


def record_finding(handle):
    with locked(handle):
        st = load(handle)
        st["boost"] = st.get("boost", 0.0) + FINDING_BOOST
        st["consecutive_empty_runs"] = 0
        return save(handle, st)


def mark_tier_run(handle, tier):
    with locked(handle):
        st = load(handle)
        key = "last_tier1_run" if str(tier) == "1" else "last_tier2_run"
        st[key] = _now()
        st["tier"] = int(tier)
        return save(handle, st)


def _load_catalog():
    p = STATE / "catalog.json"
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8")).get("programs", {})
    except ValueError:
        return {}


def cmd_rank(only_eligible):
    progs = _load_catalog()
    rows = []
    for handle, p in progs.items():
        if only_eligible and not p.get("tier_eligible"):
            continue
        rows.append((handle, effective_score(handle, p.get("score", 0.0))))
    rows.sort(key=lambda kv: kv[1], reverse=True)
    for handle, eff in rows:
        print(handle)


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    cmd = a[0]
    if cmd == "delta" and len(a) == 3:
        record_delta(a[1], int(a[2]))
    elif cmd == "empty" and len(a) == 2:
        record_empty(a[1])
    elif cmd == "finding" and len(a) == 2:
        record_finding(a[1])
    elif cmd == "tier-run" and len(a) == 3:
        mark_tier_run(a[1], a[2])
    elif cmd == "effective" and len(a) == 3:
        print(effective_score(a[1], float(a[2])))
    elif cmd == "get" and len(a) == 2:
        print(json.dumps(load(a[1]), indent=2))
    elif cmd == "rank":
        cmd_rank("--eligible" in a)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
