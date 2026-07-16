#!/usr/bin/env bash
#
# recon.sh — wrapper de recon com trava de escopo.
# Lê targets/<programa>/scope.txt, roda o pipeline e grava em loot/<programa>/.
#
# Filosofia: NUNCA sai do escopo. Wildcards viram raiz de enum; qualquer
# host que caia em out-of-scope.txt é descartado antes de qualquer sonda.
# Cada tool é opcional — se não estiver instalada, o passo é pulado, não quebra.
#
# Fontes de subdomínio (união, tudo passa por in_scope_filter):
#   subfinder (passivo) + crt.sh (cert transparency) + AXFR (zone transfer).
# Enriquecimento: registros DNS (NS/MX/TXT/SOA), URLs históricas (gau/waybackurls).
# Técnicas destiladas do Tier 3 em playbook/refs/anthropic-cyber-skills/.
#
# Uso:
#   ./bin/recon.sh <programa>
#   ./bin/recon.sh acme
#
# Requer (instala o que tiver): subfinder, httpx, katana, nuclei, anew
# Opcionais (habilitam passos extras): dig, jq, curl, gau|waybackurls
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/_scope.sh"   # scope-guard compartilhado: have/log/skip + filtros
PROG="${1:-}"
[ -z "$PROG" ] && { echo "uso: $0 <programa>"; exit 1; }

TDIR="$ROOT/targets/$PROG"
LDIR="$ROOT/loot/$PROG"
SCOPE="$TDIR/scope.txt"
OOS="$TDIR/out-of-scope.txt"

[ -f "$SCOPE" ] || { echo "sem scope.txt em $TDIR — rode h1sync.py antes"; exit 1; }
mkdir -p "$LDIR"

# --- tunables de performance (ajustáveis por .env) --------------------------
# Todos os loops raiz-por-raiz rodam em paralelo (RECON_PARALLEL) e toda sonda
# tem TETO de tempo — nenhum alvo lento pode mais comer horas. Scope-guard
# permanece intacto: cada host achado ainda passa por in_scope_filter.
RECON_PARALLEL="${RECON_PARALLEL:-8}"        # raízes processadas em paralelo (crt.sh/dig)
SUBFINDER_TIMEOUT="${SUBFINDER_TIMEOUT:-15}" # seg antes de timeout por fonte
SUBFINDER_MAXTIME="${SUBFINDER_MAXTIME:-3}"  # min máx. de enumeração (global)
CRTSH_MAXTIME="${CRTSH_MAXTIME:-15}"         # seg máx. por curl à crt.sh
DIG_TIMEOUT="${DIG_TIMEOUT:-2}"              # seg por query dig (+time)
DIG_TRIES="${DIG_TRIES:-1}"                  # tentativas por query dig (+tries)
HTTPX_TIMEOUT="${HTTPX_TIMEOUT:-8}"          # seg por probe httpx
HTTPX_THREADS="${HTTPX_THREADS:-50}"         # threads httpx
HTTPX_MAXTIME="${HTTPX_MAXTIME:-300}"        # seg máx. global do httpx (teto duro)
GAU_MAXTIME="${GAU_MAXTIME:-120}"            # seg máx. total do gau

# --- normaliza escopo (via lib) ---------------------------------------------
# wildcards (*.dominio) viram dominio raiz para enum; url/host vão direto.
scope_roots "$SCOPE" > "$LDIR/roots.txt"
OOS_RE="$(scope_oos_regex "$OOS")"

# mantém só o que casa uma raiz in-scope e NÃO casa out-of-scope
in_scope_filter() { scope_filter "$LDIR/roots.txt" "$OOS_RE"; }

log "programa: $PROG"
log "raízes in-scope: $(wc -l < "$LDIR/roots.txt")"

# --- 1. subdomínios (multi-fonte, todos scope-filtered) ---------------------
: > "$LDIR/subs.raw"

# 1a. subfinder (passivo)
if have subfinder; then
  # ATENÇÃO: subfinder v2.14 aplica -max-time POR DOMÍNIO quando usa -dL, então
  # não limita o tempo global. O `timeout` externo é o freio real; subfinder
  # streamma achados conforme encontra, então cortar preserva o que já veio.
  sf_secs=$(( SUBFINDER_MAXTIME * 60 ))
  log "subfinder (hard-cap=${sf_secs}s, timeout/fonte=${SUBFINDER_TIMEOUT}s)..."
  timeout "$sf_secs" subfinder -dL "$LDIR/roots.txt" -silent \
    -timeout "$SUBFINDER_TIMEOUT" -max-time "$SUBFINDER_MAXTIME" 2>/dev/null \
    | in_scope_filter >> "$LDIR/subs.raw" || true
else
  skip subfinder
fi

# 1b. crt.sh — certificate transparency (passivo, sem instalar nada)
if have curl; then
  log "crt.sh (cert transparency, -P${RECON_PARALLEL} max-time=${CRTSH_MAXTIME}s)..."
  export CRTSH_MAXTIME
  # cada raiz é consultada em paralelo (xargs -P); a saída bruta de todas as
  # raízes é depois normalizada e re-filtrada por escopo antes do pool.
  grep -v '^[[:space:]]*$' "$LDIR/roots.txt" \
    | xargs -r -P "$RECON_PARALLEL" -I{} bash -c '
        root="$1"
        body="$(curl -fsS --max-time "${CRTSH_MAXTIME:-15}" "https://crt.sh/?q=%25.${root}&output=json" 2>/dev/null || true)"
        [ -z "$body" ] && exit 0
        if command -v jq >/dev/null 2>&1; then
          printf "%s" "$body" | jq -r ".[].name_value" 2>/dev/null
        else
          printf "%s" "$body" | grep -oE "\"name_value\":\"[^\"]*\"" | cut -d"\"" -f4
        fi
      ' _ {} \
    | sed 's/\\n/\n/g; s/^\*\.//; s/^ *//; s/ *$//' \
    | in_scope_filter >> "$LDIR/subs.raw" || true
else
  skip curl
fi

# 1c. AXFR — zone transfer contra os NS autoritativos das raízes in-scope.
#     Só toca infra que serve o domínio in-scope; qualquer host achado é
#     re-filtrado por escopo antes de entrar no pool.
if have dig; then
  log "DNS records + AXFR (zone transfer, -P${RECON_PARALLEL} +time=${DIG_TIMEOUT} +tries=${DIG_TRIES})..."
  mkdir -p "$LDIR/dns" "$LDIR/dns/.parts"
  rm -f "$LDIR/dns/.parts/"* 2>/dev/null || true
  export DIG_TIMEOUT DIG_TRIES LDIR
  # cada raiz roda em paralelo; grava seus records/axfr em arquivo próprio
  # (sem race de append) e imprime hostnames do AXFR em stdout para o pool.
  DG="+time=$DIG_TIMEOUT +tries=$DIG_TRIES"
  export DG
  grep -v '^[[:space:]]*$' "$LDIR/roots.txt" \
    | xargs -r -P "$RECON_PARALLEL" -I{} bash -c '
        root="$1"; parts="$LDIR/dns/.parts"
        {
          echo "### $root";
          echo "# NS";  dig $DG +short NS  "$root";
          echo "# SOA"; dig $DG +short SOA "$root";
          echo "# MX";  dig $DG +short MX  "$root";
          echo "# TXT"; dig $DG +short TXT "$root";
          echo;
        } > "$parts/rec-$root.txt" 2>/dev/null || true
        for ns in $(dig $DG +short NS "$root" 2>/dev/null); do
          out="$(dig $DG +noall +answer AXFR "$root" "@${ns%.}" 2>/dev/null || true)"
          [ -z "$out" ] && continue
          { echo "### AXFR OK: $root @ $ns"; printf "%s\n" "$out"; } >> "$parts/axfr-$root.txt"
          printf "%s\n" "$out" | awk "{print \$1}" | sed "s/\.\$//"
        done
      ' _ {} \
    | in_scope_filter >> "$LDIR/subs.raw" || true
  # consolida as partes (ordem estável) nos arquivos finais
  cat "$LDIR/dns/.parts/"rec-*.txt  > "$LDIR/dns/records.txt" 2>/dev/null || : > "$LDIR/dns/records.txt"
  cat "$LDIR/dns/.parts/"axfr-*.txt > "$LDIR/dns/axfr.txt"    2>/dev/null || : > "$LDIR/dns/axfr.txt"
  rm -rf "$LDIR/dns/.parts" 2>/dev/null || true
  [ -s "$LDIR/dns/axfr.txt" ] && log "AXFR: zone transfer aberto! ver loot/$PROG/dns/axfr.txt"
else
  skip dig
fi

# consolida subdomínios
sort -u "$LDIR/subs.raw" > "$LDIR/subs.txt"
[ -s "$LDIR/subs.txt" ] || cp "$LDIR/roots.txt" "$LDIR/subs.txt"
log "subs (multi-fonte): $(wc -l < "$LDIR/subs.txt")"

# --- 2. hosts vivos ---------------------------------------------------------
if have httpx; then
  log "httpx (probe + tech, timeout=${HTTPX_TIMEOUT}s t=${HTTPX_THREADS} cap=${HTTPX_MAXTIME}s)..."
  timeout "$HTTPX_MAXTIME" httpx -l "$LDIR/subs.txt" -silent -td -sc -title \
    -timeout "$HTTPX_TIMEOUT" -t "$HTTPX_THREADS" 2>/dev/null > "$LDIR/live.txt" || true
  awk '{print $1}' "$LDIR/live.txt" | sort -u > "$LDIR/live-urls.txt"
  log "vivos: $(wc -l < "$LDIR/live-urls.txt")"
else
  skip httpx
  sed 's#^#https://#' "$LDIR/subs.txt" > "$LDIR/live-urls.txt"
fi

# --- 3. endpoints: crawl (katana) + histórico (gau/waybackurls) -------------
: > "$LDIR/urls.raw"

# RECON_NO_KATANA=1 pula o crawl (usado pelo Tier 1, que é só descoberta leve).
if [ "${RECON_NO_KATANA:-}" = 1 ]; then
  skip "katana (RECON_NO_KATANA=1)"
elif have katana; then
  log "katana (crawl)..."
  katana -list "$LDIR/live-urls.txt" -silent -jc -d 2 2>/dev/null \
    | in_scope_filter >> "$LDIR/urls.raw" || true
else
  skip katana
fi

# URLs históricas — endpoints removidos/esquecidos (passivo)
if have gau; then
  log "gau (wayback/otx histórico, teto=${GAU_MAXTIME}s)..."
  timeout "$GAU_MAXTIME" gau --threads 5 < "$LDIR/roots.txt" 2>/dev/null | in_scope_filter >> "$LDIR/urls.raw" || true
elif have waybackurls; then
  log "waybackurls (histórico, teto=${GAU_MAXTIME}s)..."
  timeout "$GAU_MAXTIME" waybackurls < "$LDIR/roots.txt" 2>/dev/null | in_scope_filter >> "$LDIR/urls.raw" || true
else
  skip "gau/waybackurls"
fi

if [ -s "$LDIR/urls.raw" ]; then
  sort -u "$LDIR/urls.raw" > "$LDIR/urls.txt"
  log "urls (crawl+histórico): $(wc -l < "$LDIR/urls.txt")"
fi

# --- 4. nuclei (baixa severidade primeiro, sem barulho) ---------------------
# RECON_NO_NUCLEI=1 pula o nuclei (Tier 1 não roda scan pesado; fica no Tier 2,
# serializado). Backward-compat: sem a env, comportamento é o de sempre.
if [ "${RECON_NO_NUCLEI:-}" = 1 ]; then
  skip "nuclei (RECON_NO_NUCLEI=1)"
elif have nuclei; then
  log "nuclei (info,low,medium)..."
  nuclei -l "$LDIR/live-urls.txt" -severity info,low,medium \
    -o "$LDIR/nuclei.txt" -silent 2>/dev/null || true
  log "achados nuclei: $(wc -l < "$LDIR/nuclei.txt" 2>/dev/null || echo 0)"
else
  skip nuclei
fi

log "loot em: $LDIR/"
echo -e "\033[1;32m[done]\033[0m recon de '$PROG' concluído."
