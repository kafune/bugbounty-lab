#!/usr/bin/env bash
#
# scope-monitor.sh — diff de ESCOPO (não de superfície).
# Versiona cada targets/<handle>/scope.txt e emite SÓ o host in-scope NOVO
# desde a última run. Delta de escopo = ativo que ninguém peneirou ainda:
# o sinal mais subestimado do bounty. É o padrão do monitor.sh aplicado ao
# catálogo de escopo em vez do alvo. Roda no Tier 0.
#
# Uso:
#   ./bin/scope-monitor.sh <handle>    # um programa
#   ./bin/scope-monitor.sh             # todos em targets/
#
# Baseline por programa em state/scope/<handle>.txt (git-ignored).
# Se houver delta e webhook configurado (.env), dispara bin/notify.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/_scope.sh"   # have/log/skip/ok + normalizadores de escopo
NOTIFY="$ROOT/bin/notify.sh"
STATE="$ROOT/state/scope"
mkdir -p "$STATE"

# Normaliza um scope.txt para o conjunto comparável: dedup + ordenado.
# (mantém a linha crua — wildcard, url ou host — pra fidelidade do delta)
norm_scope() { grep -v '^[[:space:]]*$' "$1" 2>/dev/null | sort -u; }

monitor_one() {
  local prog="$1"
  local scope="$ROOT/targets/$prog/scope.txt"
  [ -f "$scope" ] || { echo "[skip] $prog sem scope.txt"; return; }

  local prev="$STATE/$prog.txt"
  if [ ! -f "$prev" ]; then
    norm_scope "$scope" > "$prev"
    log "$prog: baseline de escopo semeado ($(grep -c . "$prev") ativos)"
    return
  fi

  local new
  new="$(comm -13 <(norm_scope "$prev") <(norm_scope "$scope") || true)"
  if [ -z "$new" ]; then
    log "$prog: escopo estável."
    return
  fi

  local count
  count="$(printf '%s\n' "$new" | grep -c .)"
  ok "$prog: +$count ativo(s) in-scope NOVO(s) no escopo"
  printf '%s\n' "$new" | sed 's/^/    /'

  # atualiza baseline (união prev+atual)
  sort -u "$prev" <(norm_scope "$scope") -o "$prev"

  if [ -f "$NOTIFY" ]; then
    local msg
    msg="$(printf '[bugbounty-lab] SCOPE_EXPANDED %s: +%d ativo(s) in-scope\n%s' \
           "$prog" "$count" "$(printf '%s\n' "$new")")"
    bash "$NOTIFY" "$msg" || true
  fi
}

if [ -n "${1:-}" ]; then
  monitor_one "$1"
else
  log "scope-monitor: iterando targets/"
  for d in "$ROOT"/targets/*/; do
    prog="$(basename "$d")"
    [ "$prog" = "_EXAMPLE" ] && continue
    monitor_one "$prog"
  done
fi
