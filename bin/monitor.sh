#!/usr/bin/env bash
#
# monitor.sh — monitoramento contínuo com diff contra baseline.
# Re-roda o recon (scope-guarded) e emite SÓ o que é novo desde a última run.
# É daqui que saem os bugs de bounty: subdomínio/endpoint/nuclei NOVO.
#
# Uso:
#   ./bin/monitor.sh <programa>        # um programa
#   ./bin/monitor.sh                   # todos em targets/
#
# Baseline por programa em loot/<prog>/.baseline/. Deltas em loot/<prog>/new-<data>-*.txt.
# Se houver delta e webhook configurado (.env), dispara bin/notify.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/_scope.sh"   # have/log/skip/ok
NOTIFY="$ROOT/bin/notify.sh"
DATE="$(date +%Y%m%d-%H%M%S)"

# arquivos de recon que vale versionar no baseline e diffar
TRACKED="subs.txt live-urls.txt urls.txt nuclei.txt"

# emite linhas de <fresh> ausentes em <baseline>, e ATUALIZA o baseline.
# usa anew se existir (append+print-new atômico); senão comm.
diff_new() {
  local fresh="$1" base="$2"
  [ -f "$fresh" ] || return 0
  if [ ! -f "$base" ]; then           # primeira run: tudo é "novo"? não — só semeia baseline.
    cp "$fresh" "$base"; return 0
  fi
  if have anew; then
    anew "$base" < "$fresh"           # imprime novas em stdout, já faz append no base
  else
    comm -13 <(sort -u "$base") <(sort -u "$fresh")
    sort -u "$base" "$fresh" -o "$base"
  fi
}

monitor_one() {
  local prog="$1"
  local ldir="$ROOT/loot/$prog" bdir="$ROOT/loot/$prog/.baseline"
  [ -f "$ROOT/targets/$prog/scope.txt" ] || { echo "[skip] $prog sem scope.txt"; return; }
  mkdir -p "$bdir"

  log "monitor: $prog — rodando recon..."
  bash "$ROOT/bin/recon.sh" "$prog" >/dev/null 2>&1 || true

  local delta_total=0 summary=""
  for f in $TRACKED; do
    local out new_count
    out="$ldir/new-$DATE-${f%.txt}.txt"
    diff_new "$ldir/$f" "$bdir/$f" > "$out" || true
    new_count="$(grep -c . "$out" 2>/dev/null)" || new_count=0
    if [ "$new_count" -gt 0 ]; then
      delta_total=$((delta_total + new_count))
      summary="${summary}  +${new_count} ${f%.txt}\n"
      log "  novo em ${f%.txt}: $new_count"
    else
      rm -f "$out"      # sem delta, não deixa arquivo vazio poluindo
    fi
  done

  if [ "$delta_total" -gt 0 ]; then
    ok "$prog: $delta_total novidades (loot/$prog/new-$DATE-*.txt)"
    if [ -f "$NOTIFY" ]; then
      local msg
      msg="$(printf '[bugbounty-lab] %s: %d novidades\n%b' "$prog" "$delta_total" "$summary")"
      bash "$NOTIFY" "$msg" || true
    fi
  else
    log "$prog: sem mudança de superfície."
  fi
}

if [ -n "${1:-}" ]; then
  monitor_one "$1"
else
  log "monitor-all: iterando targets/"
  for d in "$ROOT"/targets/*/; do
    prog="$(basename "$d")"
    [ "$prog" = "_EXAMPLE" ] && continue
    monitor_one "$prog"
  done
fi
