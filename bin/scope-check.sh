#!/usr/bin/env bash
#
# scope-check.sh — pré-flight de escopo. Use SEMPRE antes de tocar um host.
# Exit 0 = in-scope (pode prosseguir). Exit 1 = fora de escopo (PARE).
#
# Uso:
#   bash bin/scope-check.sh <host|url> <handle>
#   bash bin/scope-check.sh api.acme.com acme
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/_scope.sh"

HOST="${1:-}"; PROG="${2:-}"
[ -z "$HOST" ] || [ -z "$PROG" ] && { echo "uso: $0 <host|url> <handle>"; exit 2; }

SCOPE="$ROOT/targets/$PROG/scope.txt"
OOS="$ROOT/targets/$PROG/out-of-scope.txt"
[ -f "$SCOPE" ] || { echo "sem scope.txt para '$PROG' — rode 'make sync HANDLE=$PROG'"; exit 2; }

if host_in_scope "$HOST" "$SCOPE" "$OOS"; then
  echo -e "\033[1;32m[in-scope]\033[0m $HOST ✓ ($PROG) — pode prosseguir"
  exit 0
else
  echo -e "\033[1;31m[FORA DE ESCOPO]\033[0m $HOST ✗ ($PROG) — NÃO toque neste host"
  exit 1
fi
