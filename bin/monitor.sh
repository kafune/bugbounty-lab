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

monitor_one() (
  local prog="$1"
  local ldir="$ROOT/loot/$prog" bdir="$ROOT/loot/$prog/.baseline"
  [ -f "$ROOT/targets/$prog/scope.txt" ] || { echo "[skip] $prog sem scope.txt"; return; }
  mkdir -p "$bdir"

  local lock_dir="$ROOT/state/locks"
  mkdir -p "$lock_dir"
  exec 9>"$lock_dir/$prog.lock"
  if ! flock -n 9; then
    error "$prog: outro recon ja esta usando este handle"
    return 75
  fi

  log "monitor: $prog — rodando recon..."
  # Nao atualiza baseline nem estado quando o recon falha. A saida permanece no
  # journal para que OnFailure tenha diagnostico util.
  bash "$ROOT/bin/recon.sh" "$prog"

  # Diffa TODOS os tracks pro disco; conta cada um. Classifica por tier de sinal:
  #   ALTO   nuclei (hit novo = candidato a report), subs (superfície nova)
  #   MÉDIO  live-urls (host que subiu agora)
  #   RUÍDO  urls (colheita histórica do gau/wayback; muda a cada run)
  # Só sinal ALTO/MÉDIO dispara o webhook. urls continua gravado no disco pra
  # grep/gf posterior, mas vira rodapé — nunca dispara ping sozinho.
  local n_subs=0 n_live=0 n_urls=0 n_nuclei=0
  for f in $TRACKED; do
    local out c
    out="$ldir/new-$DATE-${f%.txt}.txt"
    if ! diff_new "$ldir/$f" "$bdir/$f" > "$out"; then
      error "$prog: falha atualizando baseline de $f"
      return 1
    fi
    c="$(grep -c . "$out" 2>/dev/null)" || c=0
    if [ "$c" -gt 0 ]; then
      log "  novo em ${f%.txt}: $c"
      case "$f" in
        subs.txt)      n_subs=$c ;;
        live-urls.txt) n_live=$c ;;
        urls.txt)      n_urls=$c ;;
        nuclei.txt)    n_nuclei=$c ;;
      esac
    else
      rm -f "$out"      # sem delta, não deixa arquivo vazio poluindo
    fi
  done

  # Headline ordenada por sinal (alto→médio); urls (firehose) só como rodapé.
  local signal_total=$((n_nuclei + n_subs + n_live))
  local headline=""
  [ "$n_nuclei" -gt 0 ] && headline="${headline} · 🔴 +${n_nuclei} nuclei"
  [ "$n_subs"   -gt 0 ] && headline="${headline} · 🟠 +${n_subs} subs"
  [ "$n_live"   -gt 0 ] && headline="${headline} · 🟡 +${n_live} live-urls"
  headline="${headline# · }"                    # tira o separador inicial
  local footer=""
  [ "$n_urls" -gt 0 ] && footer="  (+${n_urls} urls → disco)"

  if [ "$signal_total" -gt 0 ]; then
    ok "$prog: ${headline}${footer} (loot/$prog/new-$DATE-*.txt)"
    if [ -f "$NOTIFY" ]; then
      local msg
      msg="$(printf '[bugbounty-lab] %s: %s%s' "$prog" "$headline" "$footer")"
      bash "$NOTIFY" "$msg" || true
    fi
  elif [ "$n_urls" -gt 0 ]; then
    log "$prog: só +${n_urls} urls (firehose gau) — gravado no disco, sem ping."
  else
    log "$prog: sem mudança de superfície."
  fi
)

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
