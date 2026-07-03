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
  log "subfinder..."
  subfinder -dL "$LDIR/roots.txt" -silent 2>/dev/null \
    | in_scope_filter >> "$LDIR/subs.raw" || true
else
  skip subfinder
fi

# 1b. crt.sh — certificate transparency (passivo, sem instalar nada)
if have curl; then
  log "crt.sh (cert transparency)..."
  while read -r root; do
    [ -z "$root" ] && continue
    body="$(curl -fsS --max-time 25 "https://crt.sh/?q=%25.${root}&output=json" 2>/dev/null || true)"
    [ -z "$body" ] && continue
    if have jq; then
      printf '%s' "$body" | jq -r '.[].name_value' 2>/dev/null
    else
      printf '%s' "$body" | grep -oE '"name_value":"[^"]*"' | cut -d'"' -f4
    fi
  done < "$LDIR/roots.txt" \
    | sed 's/\\n/\n/g; s/^\*\.//; s/^ *//; s/ *$//' \
    | in_scope_filter >> "$LDIR/subs.raw" || true
else
  skip curl
fi

# 1c. AXFR — zone transfer contra os NS autoritativos das raízes in-scope.
#     Só toca infra que serve o domínio in-scope; qualquer host achado é
#     re-filtrado por escopo antes de entrar no pool.
if have dig; then
  log "DNS records + AXFR (zone transfer)..."
  mkdir -p "$LDIR/dns"
  : > "$LDIR/dns/records.txt"
  : > "$LDIR/dns/axfr.txt"
  while read -r root; do
    [ -z "$root" ] && continue
    {
      echo "### $root";
      echo "# NS";  dig +short NS  "$root";
      echo "# SOA"; dig +short SOA "$root";
      echo "# MX";  dig +short MX  "$root";
      echo "# TXT"; dig +short TXT "$root";
      echo;
    } >> "$LDIR/dns/records.txt" 2>/dev/null || true
    # tenta AXFR em cada NS
    for ns in $(dig +short NS "$root" 2>/dev/null); do
      out="$(dig +noall +answer AXFR "$root" "@${ns%.}" 2>/dev/null || true)"
      if [ -n "$out" ]; then
        echo "### AXFR OK: $root @ $ns" >> "$LDIR/dns/axfr.txt"
        printf '%s\n' "$out" >> "$LDIR/dns/axfr.txt"
        # hostnames do dump entram no pool (re-filtrados)
        printf '%s\n' "$out" | awk '{print $1}' | sed 's/\.$//'
      fi
    done
  done < "$LDIR/roots.txt" | in_scope_filter >> "$LDIR/subs.raw" || true
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
  log "httpx (probe + tech)..."
  httpx -l "$LDIR/subs.txt" -silent -td -sc -title 2>/dev/null > "$LDIR/live.txt"
  awk '{print $1}' "$LDIR/live.txt" | sort -u > "$LDIR/live-urls.txt"
  log "vivos: $(wc -l < "$LDIR/live-urls.txt")"
else
  skip httpx
  sed 's#^#https://#' "$LDIR/subs.txt" > "$LDIR/live-urls.txt"
fi

# --- 3. endpoints: crawl (katana) + histórico (gau/waybackurls) -------------
: > "$LDIR/urls.raw"

if have katana; then
  log "katana (crawl)..."
  katana -list "$LDIR/live-urls.txt" -silent -jc -d 2 2>/dev/null \
    | in_scope_filter >> "$LDIR/urls.raw" || true
else
  skip katana
fi

# URLs históricas — endpoints removidos/esquecidos (passivo)
if have gau; then
  log "gau (wayback/otx histórico)..."
  gau --threads 5 < "$LDIR/roots.txt" 2>/dev/null | in_scope_filter >> "$LDIR/urls.raw" || true
elif have waybackurls; then
  log "waybackurls (histórico)..."
  waybackurls < "$LDIR/roots.txt" 2>/dev/null | in_scope_filter >> "$LDIR/urls.raw" || true
else
  skip "gau/waybackurls"
fi

if [ -s "$LDIR/urls.raw" ]; then
  sort -u "$LDIR/urls.raw" > "$LDIR/urls.txt"
  log "urls (crawl+histórico): $(wc -l < "$LDIR/urls.txt")"
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
