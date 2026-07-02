#!/usr/bin/env bash
#
# recon.sh — wrapper de recon com trava de escopo.
# Lê targets/<programa>/scope.txt, roda o pipeline e grava em loot/<programa>/.
#
# Filosofia: NUNCA sai do escopo. Wildcards viram raiz de enum; qualquer
# host que caia em out-of-scope.txt é descartado antes de qualquer sonda.
# Cada tool é opcional — se não estiver instalada, o passo é pulado, não quebra.
#
# Uso:
#   ./bin/recon.sh <programa>
#   ./bin/recon.sh acme
#
# Requer (instala o que tiver): subfinder, httpx, katana, nuclei, anew
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

# --- normaliza escopo (via lib) ---------------------------------------------
# wildcards (*.dominio) viram dominio raiz para enum; url/host vão direto.
scope_roots "$SCOPE" > "$LDIR/roots.txt"
OOS_RE="$(scope_oos_regex "$OOS")"

# mantém só o que casa uma raiz in-scope e NÃO casa out-of-scope
in_scope_filter() { scope_filter "$LDIR/roots.txt" "$OOS_RE"; }

log "programa: $PROG"
log "raízes in-scope: $(wc -l < "$LDIR/roots.txt")"

# --- 1. subdomínios ---------------------------------------------------------
if have subfinder; then
  log "subfinder..."
  subfinder -dL "$LDIR/roots.txt" -silent 2>/dev/null \
    | in_scope_filter | sort -u > "$LDIR/subs.txt"
  log "subs: $(wc -l < "$LDIR/subs.txt")"
else
  skip subfinder
  cp "$LDIR/roots.txt" "$LDIR/subs.txt"
fi

# --- 2. hosts vivos ---------------------------------------------------------
if have httpx; then
  log "httpx (probe + tech)..."
  httpx -l "$LDIR/subs.txt" -silent -td -sc -title 2>/dev/null > "$LDIR/live.txt"
  awk '{print $1}' "$LDIR/live.txt" | sort -u > "$LDIR/live-urls.txt"
  log "vivos: $(wc -l < "$LDIR/live-urls.txt")"
else
  skip httpx
  sed 's#^#https://#' "$LDIR/subs.txt" > "$LDIR/live-urls.txt"
fi

# --- 3. crawl de endpoints --------------------------------------------------
if have katana; then
  log "katana (crawl)..."
  katana -list "$LDIR/live-urls.txt" -silent -jc -d 2 2>/dev/null \
    | in_scope_filter | sort -u > "$LDIR/urls.txt"
  log "urls: $(wc -l < "$LDIR/urls.txt")"
else
  skip katana
fi

# --- 4. nuclei (baixa severidade primeiro, sem barulho) ---------------------
if have nuclei; then
  log "nuclei (info,low,medium)..."
  nuclei -l "$LDIR/live-urls.txt" -severity info,low,medium \
    -o "$LDIR/nuclei.txt" -silent 2>/dev/null || true
  log "achados nuclei: $(wc -l < "$LDIR/nuclei.txt" 2>/dev/null || echo 0)"
else
  skip nuclei
fi

log "loot em: $LDIR/"
echo -e "\033[1;32m[done]\033[0m recon de '$PROG' concluído."
