#!/usr/bin/env bash
# Phase 6 — test a Firebase Storage bucket for unauth access.
# The GCS XML API often denies anon list, but the Firebase REST API (/v0/b/<bucket>/o) frequently doesn't.
#
# Usage:
#   H1USER=you bash firebase-storage.sh <bucket.appspot.com> list
#   H1USER=you bash firebase-storage.sh <bucket.appspot.com> read  "<object/name.ext>"
#   H1USER=you bash firebase-storage.sh <bucket.appspot.com> write-poc        # OUTWARD MUTATION — see below
#
# write-poc uploads ONE uniquely-named harmless marker and never overwrites anything.
# It is gated behind I_HAVE_USER_AUTHORIZATION=yes because writing to a target's storage is an
# outward, hard-to-reverse action — get explicit user sign-off first.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/_lib.sh"
BK="${1:?usage: bash firebase-storage.sh <bucket> <list|read <obj>|write-poc>}"
CMD="${2:?need a subcommand: list | read <obj> | write-poc}"
API="https://firebasestorage.googleapis.com/v0/b/$BK/o"

enc(){ python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }

case "$CMD" in
  list)
    echo "== GCS XML API (often denies anon) =="
    curl "${CURL_BASE[@]}" -o /dev/null -w '  storage.googleapis.com/%{http_code}\n' "https://storage.googleapis.com/$BK/"
    echo "== Firebase REST list =="
    tok=""; total=0
    for i in $(seq 1 30); do
      url="$API?maxResults=1000"; [ -n "$tok" ] && url="$url&pageToken=$tok"
      curl "${CURL_BASE[@]}" "$url" -o /tmp/fb.$$
      cnt=$(python3 -c "import json;print(len(json.load(open('/tmp/fb.$$')).get('items',[])))" 2>/dev/null||echo 0)
      python3 -c "import json;[print(i['name']) for i in json.load(open('/tmp/fb.$$')).get('items',[])]" 2>/dev/null >> /tmp/fb_all.$$
      tok=$(python3 -c "import json;print(json.load(open('/tmp/fb.$$')).get('nextPageToken',''))" 2>/dev/null)
      total=$((total+cnt)); [ -z "$tok" ] && break
    done
    echo "  objects listed: $total"
    echo "  top prefixes:"; sed -E 's#/.*##' /tmp/fb_all.$$ 2>/dev/null | sort | uniq -c | sort -rn | head -15
    echo "  sensitive-looking:"; grep -iE 'doc|cpf|rg|selfie|kyc|user|backup|\.(pdf|csv|json|zip|env|apk|sql)|secret|key|token|cred' /tmp/fb_all.$$ 2>/dev/null | head -20
    echo "  full list saved: /tmp/fb_all.$$"; rm -f /tmp/fb.$$
    ;;
  read)
    OBJ="${3:?read needs an object name}"; e="$(enc "$OBJ")"
    curl "${CURL_BASE[@]}" -o /tmp/fbo.$$ -w 'read -> HTTP %{http_code} %{size_download}b %{content_type}\n' "$API/$e?alt=media"
    echo "first bytes:"; head -c 200 /tmp/fbo.$$; echo; rm -f /tmp/fbo.$$
    ;;
  write-poc)
    if [ "${I_HAVE_USER_AUTHORIZATION:-no}" != "yes" ]; then
      echo "REFUSING: writing to a target bucket is an outward mutation."
      echo "Get explicit user authorization, then re-run with:  I_HAVE_USER_AUTHORIZATION=yes bash $0 $BK write-poc"
      exit 3
    fi
    RAND=$(head -c6 /dev/urandom | xxd -p)
    NAME="bbtest-${H1USER}-${RAND}.txt"
    BODY="Authorized HackerOne write PoC. Researcher: ${H1USER}. Harmless marker, safe to delete."
    echo -n "$BODY" > /tmp/poc.$$
    echo "== upload (Firebase simple) =="
    curl "${CURL_BASE[@]}" -H 'Content-Type: text/plain' --data-binary @/tmp/poc.$$ \
      -o /tmp/up.$$ -w 'HTTP %{http_code}\n' "$API?name=$(enc "$NAME")&uploadType=media"
    cat /tmp/up.$$; echo
    echo "== verify read-back =="
    curl "${CURL_BASE[@]}" -o /dev/null -w 'readback HTTP %{http_code}\n' "$API/$(enc "$NAME")?alt=media"
    echo "== attempt cleanup (DELETE) =="
    curl "${CURL_BASE[@]}" -X DELETE -o /dev/null -w 'delete HTTP %{http_code}\n' "$API/$(enc "$NAME")"
    rm -f /tmp/poc.$$ /tmp/up.$$
    echo "object name was: $NAME  (record it in FINDINGS)"
    ;;
  *) echo "unknown subcommand: $CMD"; exit 1;;
esac
