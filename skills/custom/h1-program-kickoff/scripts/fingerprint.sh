#!/usr/bin/env bash
# Phase 3 — fingerprint in-scope hosts.
# Usage:  H1USER=you bash fingerprint.sh hosts.txt
#         H1USER=you bash fingerprint.sh host1 host2 ...
# Input hosts may be bare ("api.example.com") or full URLs.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/_lib.sh"

if [ $# -eq 1 ] && [ -f "$1" ]; then mapfile -t HOSTS < <(awk '{print $1}' "$1" | sed 's#https\?://##; s#/.*##' | sort -u)
else HOSTS=("$@"); fi
[ ${#HOSTS[@]} -eq 0 ] && { echo "no hosts. usage: bash fingerprint.sh <hosts.txt | host...>"; exit 1; }

for h in "${HOSTS[@]}"; do
  h="${h#http*://}"; h="${h%%/*}"
  tmp="$(mktemp)"
  out="$(curl "${CURL_BASE[@]}" -D "$tmp.h" -o "$tmp" -w '%{http_code} %{size_download}b %{content_type} -> %{redirect_url}' "https://$h/")"
  title="$(grep -oiE '<title[^>]*>[^<]*' "$tmp" | head -1 | sed -E 's/<title[^>]*>//I')"
  srv="$(grep -iE '^(server|cf-ray|via|x-powered-by):' "$tmp.h" | tr '\n' ' ' | tr -d '\r')"
  loc="$(grep -iE '^location:' "$tmp.h" | tr -d '\r')"
  # classify by tell-tale signatures
  body="$(head -c 400 "$tmp")"; tag=""
  case "$body" in
    *RouteFailed*|*"route the message to a Target Endpoint"*) tag="[Apigee:no-proxy]";;
    *"RBAC: access denied"*)                                  tag="[Istio-RBAC]";;
    *"NoSuchBucket"*|*"<Error><Code>"*)                       tag="[GCS/bucket]";;
    *"Just a moment"*|*"Attention Required"*)                 tag="[Cloudflare-challenge]";;
  esac
  [ "${out%% *}" = "415" ] && grep -qi 'application/grpc' <<<"$out" && tag="[gRPC-Web]"
  printf '%-40s %s %s\n' "$h" "$out" "$tag"
  [ -n "$title" ] && printf '    title: %s\n' "$title"
  [ -n "$loc" ]   && printf '    %s\n' "$loc"
  [ -n "$srv" ]   && printf '    %s\n' "$srv"
  rm -f "$tmp" "$tmp.h"
done
