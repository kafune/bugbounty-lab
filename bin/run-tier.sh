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
bootstrap_tool_path

NOTIFY="$ROOT/bin/notify.sh"
LOCKS="$ROOT/state/locks"
mkdir -p "$LOCKS"

PY() { if [ -x "$ROOT/.venv/bin/python" ]; then "$ROOT/.venv/bin/python" "$@"; else python3 "$@"; fi; }

TIER="${1:-}"
[ -z "$TIER" ] && { echo "uso: $0 <0|1|2>"; exit 1; }

case "$TIER" in
  0) ;;
  1) require_tools subfinder httpx ;;
  2) require_tools nuclei ;;
  *) echo "tier inválido: $TIER (use 0, 1 ou 2)"; exit 1 ;;
esac

# contenção do nuclei (ajustável por .env)
NUCLEI_CONCURRENCY="${NUCLEI_CONCURRENCY:-25}"
NUCLEI_RATE_LIMIT="${NUCLEI_RATE_LIMIT:-100}"
NUCLEI_BATCH_SIZE="${NUCLEI_BATCH_SIZE:-25}"
# info/low sao majoritariamente ruido pra bounty (headers, banners, tech-detect).
# Default foca no que costuma virar report; ajuste no .env se quiser mais amplo.
NUCLEI_SEVERITY="${NUCLEI_SEVERITY:-medium,high,critical}"
NUCLEI_AUTOMATIC_SCAN="${NUCLEI_AUTOMATIC_SCAN:-1}"

# teto de wall-clock por host (rede de segurança: nenhum alvo lento eterniza o
# ciclo). recon.sh já se auto-limita por etapa; isto é o backstop de fora.
TIER1_MAX_PER_HOST="${TIER1_MAX_PER_HOST:-1200}"   # 20 min por host no Tier 1 (headroom p/ alvos grandes)
TIER2_MAX_PER_BATCH="${TIER2_MAX_PER_BATCH:-${TIER2_MAX_PER_HOST:-1800}}" # compat: nome antigo
timed() { if have timeout; then timeout "$@"; else shift; "$@"; fi; }

case "$NUCLEI_BATCH_SIZE" in
  ''|*[!0-9]*|0) error "NUCLEI_BATCH_SIZE deve ser um inteiro positivo"; exit 1 ;;
esac
case "$TIER2_MAX_PER_BATCH" in
  ''|*[!0-9]*|0) error "TIER2_MAX_PER_BATCH deve ser um inteiro positivo"; exit 1 ;;
esac

# handles tier_eligible ordenados por score efetivo (Fase D)
eligible_handles() { PY "$ROOT/bin/state.py" rank --eligible; }

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# ---------------------------------------------------------------------------
# Tier 0 — descoberta barata
# ---------------------------------------------------------------------------
run_tier0() {
  local failures=0
  log "tier0: discover + scope-monitor"
  PY "$ROOT/bin/discover.py" || { error "tier0: discover falhou"; failures=$((failures + 1)); }
  bash "$ROOT/bin/scope-monitor.sh" || { error "tier0: scope-monitor falhou"; failures=$((failures + 1)); }
  [ "$failures" -eq 0 ] || return 1
}

# ---------------------------------------------------------------------------
# Tier 1 — descoberta de superfície (subfinder+httpx), 1 recon por handle
# ---------------------------------------------------------------------------
tier1_one() {
  local h="$1"
  local scope="$ROOT/targets/$h/scope.txt"
  [ -f "$scope" ] || { log "[skip] $h sem scope.txt"; return; }

  log "tier1: $h"
  # monitor adquire o lock do handle e roda recon + diff + notify.
  local out delta rc
  if out="$(RECON_NO_KATANA=1 RECON_NO_NUCLEI=1 timed "$TIER1_MAX_PER_HOST" bash "$ROOT/bin/monitor.sh" "$h" 2>&1 </dev/null)"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$out" | strip_ansi | sed 's/^/    /'
  if [ "$rc" -ne 0 ]; then
    error "tier1 $h falhou (exit=$rc); baseline e estado nao foram atualizados"
    return "$rc"
  fi
  # `|| true` é obrigatório: sob set -e + pipefail, um grep sem match (host sem
  # novidades, ou timeout) faria a atribuição falhar e ABORTAR o tier inteiro.
  delta="$(printf '%s' "$out" | strip_ansi | grep -oE '[0-9]+ novidades' | grep -oE '[0-9]+' | head -1 || true)"
  delta="${delta:-0}"

  if [ "$delta" -gt 0 ]; then
    if ! PY "$ROOT/bin/state.py" delta "$h" "$delta" >/dev/null; then
      error "tier1 $h: falha persistindo delta no estado"
      return 1
    fi
  else
    if ! PY "$ROOT/bin/state.py" empty "$h" >/dev/null; then
      error "tier1 $h: falha persistindo run vazia no estado"
      return 1
    fi
  fi
  if ! PY "$ROOT/bin/state.py" tier-run "$h" 1 >/dev/null; then
    error "tier1 $h: falha persistindo timestamp no estado"
    return 1
  fi
}

run_tier1() {
  local handles failures=0; handles="$(eligible_handles)"
  [ -z "$handles" ] && { log "tier1: nenhum handle tier_eligible (rode discover)"; return; }
  # loop lê do fd 3 (não do stdin): ferramentas internas como httpx/nuclei
  # DRENAM o stdin herdado, o que comeria o here-string e mataria o loop após
  # o 1º host. guarda `|| log`: falha/timeout de um host não aborta o tier.
  while read -r h <&3; do
    [ -n "$h" ] || continue
    if ! tier1_one "$h"; then
      failures=$((failures + 1))
      log "[warn] tier1 $h falhou — segue"
    fi
  done 3<<< "$handles"
  [ "$failures" -eq 0 ] || { error "tier1 terminou com $failures handle(s) incompleto(s)"; return 1; }
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

tier2_one() (
  local h="$1"
  local scope="$ROOT/targets/$h/scope.txt" oos="$ROOT/targets/$h/out-of-scope.txt"
  local ldir="$ROOT/loot/$h" live="$ROOT/loot/$h/live-urls.txt"
  [ -f "$scope" ] || { log "[skip] $h sem scope.txt"; return; }
  [ -f "$live" ]  || { log "[skip] $h sem live-urls (rode tier1 antes)"; return; }

  # Compartilha o lock por handle com o Tier 1. O subshell garante unlock em
  # qualquer caminho de retorno, inclusive erro/timeout.
  exec 9>"$LOCKS/$h.lock"
  if ! flock -n 9; then
    error "tier2 $h: handle ocupado por outro recon"
    return 75
  fi

  # re-valida CADA alvo pelo scope-guard antes de tocar (sem exceção)
  local safe="$ldir/tier2-targets.txt"
  if ! scope_filter "$scope" "$oos" < "$live" > "$safe"; then
    error "tier2 $h: scope guard falhou"
    return 1
  fi
  sort -u "$safe" -o "$safe"
  local n; n="$(grep -c . "$safe" 2>/dev/null)" || n=0
  [ "$n" -eq 0 ] && { log "$h: 0 alvos in-scope após guard"; return; }

  local mode="templates completos"
  local -a mode_args=()
  if [ "$NUCLEI_AUTOMATIC_SCAN" = 1 ]; then
    mode="seleção automática por tecnologia"
    mode_args=(-automatic-scan)
  fi
  local total_batches=$(((n + NUCLEI_BATCH_SIZE - 1) / NUCLEI_BATCH_SIZE))
  log "tier2: $h — nuclei em $n alvo(s), $total_batches lote(s), $mode (sev=$NUCLEI_SEVERITY c=$NUCLEI_CONCURRENCY rl=$NUCLEI_RATE_LIMIT)"
  local bdir="$ldir/.baseline"; mkdir -p "$bdir"
  local fresh="$ldir/nuclei.current.txt" rc
  local work="$ldir/.tier2-work"
  cleanup_tier2_work() {
    find "$work" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
    rmdir "$work" 2>/dev/null || true
  }
  cleanup_tier2_work
  mkdir -p "$work"
  trap cleanup_tier2_work EXIT
  rm -f "$fresh"
  : > "$fresh"
  split -d -a 4 -l "$NUCLEI_BATCH_SIZE" "$safe" "$work/targets-"

  local batch batch_out batch_no=0 batch_targets truncated=0
  for batch in "$work"/targets-*; do
    batch_no=$((batch_no + 1))
    batch_targets="$(grep -c . "$batch" 2>/dev/null)" || batch_targets=0
    batch_out="$work/results-$batch_no.txt"
    log "tier2: $h — lote $batch_no/$total_batches ($batch_targets alvo(s))"
    if timed "$TIER2_MAX_PER_BATCH" nuclei -l "$batch" -severity "$NUCLEI_SEVERITY" \
        "${mode_args[@]}" -c "$NUCLEI_CONCURRENCY" -rate-limit "$NUCLEI_RATE_LIMIT" \
        -disable-update-check -no-color -o "$batch_out" -silent >/dev/null </dev/null; then
      rc=0
    else
      rc=$?
    fi
    if [ "$rc" -eq 124 ]; then
      # Timeout != falha. nuclei grava cada achado no -o assim que encontra,
      # entao o arquivo parcial ja contem findings validos — so a cobertura do
      # lote ficou incompleta. Preserva o que veio e segue: a proxima run
      # re-escaneia os mesmos alvos (lista inalterada) e o baseline diff pega
      # o que faltou. NAO descartar aqui era o bug reportado.
      truncated=$((truncated + 1))
      log "[warn] tier2 $h: lote $batch_no/$total_batches atingiu o teto (${TIER2_MAX_PER_BATCH}s); mantendo achados parciais"
    elif [ "$rc" -ne 0 ]; then
      rm -f "$fresh" "$batch_out"
      error "tier2 $h: nuclei falhou no lote $batch_no/$total_batches (exit=$rc); resultado parcial descartado"
      return "$rc"
    fi
    [ -f "$batch_out" ] && cat "$batch_out" >> "$fresh"
  done
  if ! sort -u "$fresh" -o "$fresh" || ! mv "$fresh" "$ldir/nuclei.txt"; then
    error "tier2 $h: falha promovendo resultado completo"
    return 1
  fi

  local new_out; new_out="$ldir/new-nuclei-$(basename "$safe" .txt).txt"
  if ! diff_new "$ldir/nuclei.txt" "$bdir/nuclei.txt" > "$new_out" 2>/dev/null; then
    error "tier2 $h: falha atualizando baseline nuclei"
    return 1
  fi
  local delta; delta="$(grep -c . "$new_out" 2>/dev/null)" || delta=0

  if [ "$delta" -gt 0 ]; then
    ok "$h: $delta achado(s) nuclei NOVO(s)"
    if ! PY "$ROOT/bin/state.py" delta "$h" "$delta" >/dev/null; then
      error "tier2 $h: falha persistindo delta no estado"
      return 1
    fi
    [ -f "$NOTIFY" ] && bash "$NOTIFY" "$(printf '[bugbounty-lab] tier2 %s: %d nuclei novo(s)' "$h" "$delta")" || true
  else
    rm -f "$new_out"
    if ! PY "$ROOT/bin/state.py" empty "$h" >/dev/null; then
      error "tier2 $h: falha persistindo run vazia no estado"
      return 1
    fi
  fi
  if ! PY "$ROOT/bin/state.py" tier-run "$h" 2 >/dev/null; then
    error "tier2 $h: falha persistindo timestamp no estado"
    return 1
  fi
  # Cobertura parcial e um resultado valido (achados preservados), nao uma
  # falha do handle — por isso retorna 0. O aviso fica no journal para revisao.
  [ "$truncated" -gt 0 ] && log "[warn] tier2 $h: $truncated lote(s) truncado(s) por tempo; cobertura parcial preservada"
  return 0
)

run_tier2() {
  # flock GLOBAL: garante um único Tier 2 no ar (nunca 2 nuclei simultâneos,
  # nem entre invocações concorrentes). Protege a VPS e evita ban do alvo.
  exec 8>"$LOCKS/tier2.global.lock"
  if ! flock -n 8; then
    log "tier2: já há um Tier 2 rodando (flock global) — saindo"; exit 0
  fi
  local handles failures=0; handles="$(eligible_handles)"
  [ -z "$handles" ] && { log "tier2: nenhum handle tier_eligible (rode discover)"; return; }
  # serializado: um handle (um nuclei) por vez; falha de um não aborta o tier.
  # fd 3 pelo mesmo motivo do tier1: nuclei drena o stdin herdado.
  while read -r h <&3; do
    [ -n "$h" ] || continue
    if ! tier2_one "$h"; then
      failures=$((failures + 1))
      log "[warn] tier2 $h falhou — segue"
    fi
  done 3<<< "$handles"
  [ "$failures" -eq 0 ] || { error "tier2 terminou com $failures handle(s) incompleto(s)"; return 1; }
}

case "$TIER" in
  0) run_tier0 ;;
  1) run_tier1 ;;
  2) run_tier2 ;;
esac

ok "tier $TIER concluído."
