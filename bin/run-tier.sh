#!/usr/bin/env bash
#
# run-tier.sh <0|1|2> — runner do loop contínuo (chamado pelos systemd timers).
#
# Seleciona os handles tier_eligible do catálogo, ordenados por score EFETIVO
# (score + boost do feedback loop), e roda o trabalho do tier. Toda sonda passa
# pelo scope-guard (_scope.sh) antes de tocar no alvo — sem exceção.
#
#   Tier 0  (barato)  discover + score + scope-monitor
#   Tier 1  (médio)   subfinder + httpx nos top-N (recon sem katana/nuclei)
#   Tier 2  (pesado)  nuclei nos top-N — FILA SERIALIZADA (flock global, 1 por vez)
#
# Contenção (VPS 4 vCPU): flock por handle (nunca 2 recons do mesmo alvo),
# flock global no Tier 2 (nunca 2 nuclei simultâneos), rate-limit conservador.
#
# Uso:
#   ./bin/run-tier.sh 0|1|2
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/_scope.sh"          # have/log/skip/ok + host_in_scope
set -a; [ -f "$ROOT/.env" ] && . "$ROOT/.env"; set +a

NOTIFY="$ROOT/bin/notify.sh"
LOCKS="$ROOT/state/locks"
mkdir -p "$LOCKS"

PY() { if [ -x "$ROOT/.venv/bin/python" ]; then "$ROOT/.venv/bin/python" "$@"; else python3 "$@"; fi; }

TIER="${1:-}"
[ -z "$TIER" ] && { echo "uso: $0 <0|1|2>"; exit 1; }

# contenção do nuclei (ajustável por .env)
NUCLEI_CONCURRENCY="${NUCLEI_CONCURRENCY:-25}"
NUCLEI_RATE_LIMIT="${NUCLEI_RATE_LIMIT:-100}"

# teto de wall-clock por host (rede de segurança: nenhum alvo lento eterniza o
# ciclo). recon.sh já se auto-limita por etapa; isto é o backstop de fora.
TIER1_MAX_PER_HOST="${TIER1_MAX_PER_HOST:-1200}"   # 20 min por host no Tier 1 (headroom p/ alvos grandes)
TIER2_MAX_PER_HOST="${TIER2_MAX_PER_HOST:-1800}"   # 30 min por host no Tier 2
timed() { if have timeout; then timeout "$@"; else shift; "$@"; fi; }

# handles tier_eligible ordenados por score efetivo (Fase D)
eligible_handles() { PY "$ROOT/bin/state.py" rank --eligible; }

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# ---------------------------------------------------------------------------
# Tier 0 — descoberta barata
# ---------------------------------------------------------------------------
run_tier0() {
  log "tier0: discover + scope-monitor"
  PY "$ROOT/bin/discover.py" || true
  bash "$ROOT/bin/scope-monitor.sh" || true
}

# ---------------------------------------------------------------------------
# Tier 1 — descoberta de superfície (subfinder+httpx), 1 recon por handle
# ---------------------------------------------------------------------------
tier1_one() {
  local h="$1"
  local scope="$ROOT/targets/$h/scope.txt"
  [ -f "$scope" ] || { log "[skip] $h sem scope.txt"; return; }

  # flock por handle: nunca dois recons do mesmo alvo em paralelo
  exec 9>"$LOCKS/$h.lock"
  if ! flock -n 9; then
    log "[skip] $h já em recon (lock)"; return
  fi

  log "tier1: $h"
  # monitor roda recon (sem katana/nuclei) + diff de superfície + notify.
  local out delta
  out="$(RECON_NO_KATANA=1 RECON_NO_NUCLEI=1 timed "$TIER1_MAX_PER_HOST" bash "$ROOT/bin/monitor.sh" "$h" 2>&1 </dev/null || true)"
  printf '%s\n' "$out" | strip_ansi | sed 's/^/    /'
  # `|| true` é obrigatório: sob set -e + pipefail, um grep sem match (host sem
  # novidades, ou timeout) faria a atribuição falhar e ABORTAR o tier inteiro.
  delta="$(printf '%s' "$out" | strip_ansi | grep -oE '[0-9]+ novidades' | grep -oE '[0-9]+' | head -1 || true)"
  delta="${delta:-0}"

  if [ "$delta" -gt 0 ]; then
    PY "$ROOT/bin/state.py" delta "$h" "$delta" >/dev/null || true
  else
    PY "$ROOT/bin/state.py" empty "$h" >/dev/null || true
  fi
  PY "$ROOT/bin/state.py" tier-run "$h" 1 >/dev/null || true
  flock -u 9
}

run_tier1() {
  local handles; handles="$(eligible_handles)"
  [ -z "$handles" ] && { log "tier1: nenhum handle tier_eligible (rode discover)"; return; }
  # loop lê do fd 3 (não do stdin): ferramentas internas como httpx/nuclei
  # DRENAM o stdin herdado, o que comeria o here-string e mataria o loop após
  # o 1º host. guarda `|| log`: falha/timeout de um host não aborta o tier.
  while read -r h <&3; do
    [ -n "$h" ] && { tier1_one "$h" || log "[warn] tier1 $h falhou — segue"; }
  done 3<<< "$handles"
}

# ---------------------------------------------------------------------------
# Tier 2 — nuclei pesado, FILA SERIALIZADA (flock global: 1 nuclei por vez)
# ---------------------------------------------------------------------------
# emite linhas de <fresh> ausentes em <base> e atualiza o base (padrão monitor).
diff_new() {
  local fresh="$1" base="$2"
  [ -f "$fresh" ] || return 0
  if [ ! -f "$base" ]; then cp "$fresh" "$base"; return 0; fi
  if have anew; then anew "$base" < "$fresh"
  else comm -13 <(sort -u "$base") <(sort -u "$fresh"); sort -u "$base" "$fresh" -o "$base"; fi
}

tier2_one() {
  local h="$1"
  local scope="$ROOT/targets/$h/scope.txt" oos="$ROOT/targets/$h/out-of-scope.txt"
  local ldir="$ROOT/loot/$h" live="$ROOT/loot/$h/live-urls.txt"
  [ -f "$scope" ] || { log "[skip] $h sem scope.txt"; return; }
  [ -f "$live" ]  || { log "[skip] $h sem live-urls (rode tier1 antes)"; return; }

  # re-valida CADA alvo pelo scope-guard antes de tocar (sem exceção)
  local safe="$ldir/tier2-targets.txt"; : > "$safe"
  while read -r u; do
    [ -z "$u" ] && continue
    host_in_scope "$u" "$scope" "$oos" && printf '%s\n' "$u" >> "$safe"
  done < "$live"
  local n; n="$(grep -c . "$safe" 2>/dev/null)" || n=0
  [ "$n" -eq 0 ] && { log "$h: 0 alvos in-scope após guard"; return; }

  if ! have nuclei; then skip nuclei; return; fi
  log "tier2: $h — nuclei em $n alvo(s) (c=$NUCLEI_CONCURRENCY rl=$NUCLEI_RATE_LIMIT)"
  local bdir="$ldir/.baseline"; mkdir -p "$bdir"
  timed "$TIER2_MAX_PER_HOST" nuclei -l "$safe" -severity info,low,medium,high,critical \
    -c "$NUCLEI_CONCURRENCY" -rate-limit "$NUCLEI_RATE_LIMIT" \
    -o "$ldir/nuclei.txt" -silent 2>/dev/null </dev/null || true

  local new_out; new_out="$ldir/new-nuclei-$(basename "$safe").txt"
  diff_new "$ldir/nuclei.txt" "$bdir/nuclei.txt" > "$new_out" 2>/dev/null || true
  local delta; delta="$(grep -c . "$new_out" 2>/dev/null)" || delta=0

  if [ "$delta" -gt 0 ]; then
    ok "$h: $delta achado(s) nuclei NOVO(s)"
    PY "$ROOT/bin/state.py" delta "$h" "$delta" >/dev/null || true
    [ -f "$NOTIFY" ] && bash "$NOTIFY" "$(printf '[bugbounty-lab] tier2 %s: %d nuclei novo(s)' "$h" "$delta")" || true
  else
    rm -f "$new_out"
    PY "$ROOT/bin/state.py" empty "$h" >/dev/null || true
  fi
  PY "$ROOT/bin/state.py" tier-run "$h" 2 >/dev/null || true
}

run_tier2() {
  # flock GLOBAL: garante um único Tier 2 no ar (nunca 2 nuclei simultâneos,
  # nem entre invocações concorrentes). Protege a VPS e evita ban do alvo.
  exec 8>"$LOCKS/tier2.global.lock"
  if ! flock -n 8; then
    log "tier2: já há um Tier 2 rodando (flock global) — saindo"; exit 0
  fi
  local handles; handles="$(eligible_handles)"
  [ -z "$handles" ] && { log "tier2: nenhum handle tier_eligible (rode discover)"; return; }
  # serializado: um handle (um nuclei) por vez; falha de um não aborta o tier.
  # fd 3 pelo mesmo motivo do tier1: nuclei drena o stdin herdado.
  while read -r h <&3; do
    [ -n "$h" ] && { tier2_one "$h" || log "[warn] tier2 $h falhou — segue"; }
  done 3<<< "$handles"
}

case "$TIER" in
  0) run_tier0 ;;
  1) run_tier1 ;;
  2) run_tier2 ;;
  *) echo "tier inválido: $TIER (use 0, 1 ou 2)"; exit 1 ;;
esac

ok "tier $TIER concluído."
