#!/usr/bin/env bash
# Shared helpers for h1-program-kickoff scripts.  source this file.
# Requires H1USER (your HackerOne handle) for attribution on every request.
#
#   export H1USER=yourname
#   # if a program requires User-Agent == username instead of a header:
#   #   export BUA="$H1USER"
#
: "${H1USER:?set H1USER to your HackerOne username (attribution)}"
# Browser UA bypasses Cloudflare bot-management; attribution rides in headers below.
BUA="${BUA:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36}"

# Common curl args (attribution kept even with a browser UA).
CURL_BASE=(-s -k -m15 -A "$BUA"
  -H "X-HackerOne-Research: $H1USER"
  -H "X-Bug-Bounty: $H1USER")

# req METHOD URL [DATA] [extra curl args...]
# prints: "METHOD path -> code size ctype | first 160 bytes of body"
req() {
  local m="$1" url="$2" data="$3"; shift 3 2>/dev/null || shift $#
  local args=("${CURL_BASE[@]}" -X "$m" "$@")
  [ -n "$data" ] && args+=(-H 'Content-Type: application/json' --data "$data")
  local tmp; tmp="$(mktemp)"
  local out; out="$(curl "${args[@]}" -o "$tmp" -w '%{http_code} %{size_download}b %{content_type}' "$url")"
  printf '%-5s %-50s %s | %s\n' "$m" "${url#*://*/}" "$out" "$(head -c 160 "$tmp" | tr '\n' ' ' | tr -d '\r')"
  rm -f "$tmp"
}

# strip ANSI (for piping httpx colored output into grep)
strip_ansi() { sed -r 's/\x1b\[[0-9;]*m//g'; }
