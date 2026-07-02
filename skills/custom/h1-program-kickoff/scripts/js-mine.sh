#!/usr/bin/env bash
# Phase 4 — pull a SPA's JS bundles, check for sourcemaps, grep for surface.
# Usage:  H1USER=you bash js-mine.sh https://app.example.com [outdir]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/_lib.sh"
B="${1:?usage: bash js-mine.sh <base-url> [outdir]}"; B="${B%/}"
OUT="${2:-js_$(echo "$B" | sed 's#https\?://##; s#[^a-zA-Z0-9]#_#g')}"
mkdir -p "$OUT"; cd "$OUT"

echo "== fetching index + assets from $B =="
curl "${CURL_BASE[@]}" "$B/" -o index.html
# collect script/asset refs (relative + absolute)
mapfile -t REFS < <(grep -oiE '(src|href)="[^"]+\.js"' index.html | sed -E 's/.*"([^"]+)"/\1/' | sort -u)
for r in "${REFS[@]}"; do
  case "$r" in http*) url="$r";; /*) url="$B$r";; *) url="$B/$r";; esac
  fn="$(basename "${r%%\?*}")"
  curl "${CURL_BASE[@]}" "$url" -o "$fn" 2>/dev/null
  mc="$(curl "${CURL_BASE[@]}" -o /dev/null -w '%{http_code}' "$url.map")"
  printf '  %-40s %8sb   .map -> %s%s\n' "$fn" "$(wc -c <"$fn" 2>/dev/null)" "$mc" \
    "$([ "$mc" = 200 ] && echo '  <== SOURCEMAP! reconstruct with sourcemap.py')"
  [ "$mc" = 200 ] && curl "${CURL_BASE[@]}" "$url.map" -o "$fn.map"
done

echo "== grepping bundles for surface =="
GREP_FILES=(*.js)
echo "-- API hosts --";        grep -ohaE 'https?://[a-zA-Z0-9._-]+\.[a-z]{2,}(/[a-zA-Z0-9._/-]*)?' "${GREP_FILES[@]}" 2>/dev/null | grep -iE 'api|/client/|/v[0-9]|cadastro|backend' | sort -u | head -40
echo "-- endpoint path constants --"; grep -ohaE '"/(api|client|v[0-9]|process|oauth|login|auth|user|account|transaction|payment|next-step|execute)[a-zA-Z0-9._/{}-]*"' "${GREP_FILES[@]}" 2>/dev/null | sort -u | head -50
echo "-- build-time env vars --";  grep -ohaE '(NX_PUBLIC|VITE|REACT_APP|NEXT_PUBLIC)_[A-Z0-9_]+' "${GREP_FILES[@]}" 2>/dev/null | sort -u | head -40
echo "-- secrets / cloud ids --";  grep -ohaE 'AIza[0-9A-Za-z_-]{35}|[a-z0-9-]+\.(appspot\.com|firebaseio\.com|web\.app)|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,}|BEGIN [A-Z ]*PRIVATE KEY' "${GREP_FILES[@]}" 2>/dev/null | sort -u | head -20
echo "-- clientIDs / UUIDs --";    grep -ohaE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "${GREP_FILES[@]}" 2>/dev/null | sort -u | head -10
echo "done. artifacts in $(pwd)"
