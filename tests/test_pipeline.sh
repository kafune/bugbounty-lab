#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/_scope.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_scope() {
  local expected="$1" candidate="$2" scope="$3" oos="$4" got=deny
  host_in_scope "$candidate" "$scope" "$oos" && got=allow
  [ "$got" = "$expected" ] || fail "$candidate: esperado=$expected obtido=$got"
  pass=$((pass + 1))
}
assert_eq() {
  local expected="$1" actual="$2" label="$3"
  [ "$actual" = "$expected" ] || fail "$label: esperado=[$expected] obtido=[$actual]"
  pass=$((pass + 1))
}

cat > "$TMP/scope.txt" <<'EOF'
example.com
*.wild.example
https://secure.example.net
https://*.tls.example.org
https://path.example.io/book/
https://port.example.dev:8443
https://excluded.example.edu
EOF
cat > "$TMP/oos.txt" <<'EOF'
blocked.wild.example
node[0-9].wild.example
https://rack[0-9].wild.example/private/*
https://path.example.io/book/private/
/global-private-*
https://excluded.example.edu
EOF

assert_scope allow example.com "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny sub.example.com "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow api.wild.example "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny wild.example "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny blocked.wild.example "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny node7.wild.example "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow node10.wild.example "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://rack3.wild.example/private/config "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow https://rack3.wild.example/public "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow https://secure.example.net "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow https://secure.example.net:443 "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://secure.example.net:8443 "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny http://secure.example.net "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://secure.example.net/global-private-token "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow https://api.tls.example.org "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny http://api.tls.example.org "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow https://path.example.io/book/42 "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://path.example.io/booking "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny path.example.io "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://path.example.io/book/private/42 "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://path.example.io/book/../admin "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://path.example.io/book/%2e%2e/admin "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope allow https://port.example.dev:8443 "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://port.example.dev:9443 "$TMP/scope.txt" "$TMP/oos.txt"
assert_scope deny https://excluded.example.edu "$TMP/scope.txt" "$TMP/oos.txt"

assert_eq $'tls.example.org\nwild.example' "$(scope_enum_roots "$TMP/scope.txt")" "wildcard roots"
assert_eq $'example.com\nhttps://excluded.example.edu\nhttps://path.example.io/book/\nhttps://port.example.dev:8443\nhttps://secure.example.net' "$(scope_seeds "$TMP/scope.txt")" "exact seeds"
assert_eq $'example.com\npath.example.io\nport.example.dev\nsecure.example.net\ntls.example.org\nwild.example' \
  "$(scope_roots "$TMP/scope.txt" "$TMP/oos.txt")" "OOS-filtered roots"
assert_eq $'api.wild.example\nexample.com' \
  "$(printf '%s\n' example.com sub.example.com api.wild.example blocked.wild.example | scope_filter "$TMP/scope.txt" "$TMP/oos.txt" | sort)" \
  "strict filter"
# linha em branco/espacos no meio do stream nao pode derrubar o filter
assert_eq $'example.com' \
  "$(printf '%s\n' example.com '' '   ' | scope_filter "$TMP/scope.txt" "$TMP/oos.txt")" \
  "filter ignora linha em branco"
# httpx emite colunas extras; o 1o campo decide, mas a linha crua e preservada
assert_eq 'https://secure.example.net [200] [title]' \
  "$(printf '%s\n' 'https://secure.example.net [200] [title]' | scope_filter "$TMP/scope.txt" "$TMP/oos.txt")" \
  "filter decide pelo 1o campo e preserva a linha"

good_axfr='example.com. 300 IN SOA ns1.example.com. hostmaster.example.com. 1 2 3 4 5'
bad_axfr='; Transfer failed.'
printf '%s\n' "$good_axfr" | axfr_has_soa || fail "AXFR valido rejeitado"
if printf '%s\n' "$bad_axfr" | axfr_has_soa; then fail "erro de AXFR aceito"; fi
pass=$((pass + 2))

mkdir -p "$TMP/home/go/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/home/go/bin/fake-bblab-tool"
chmod +x "$TMP/home/go/bin/fake-bblab-tool"
OLD_PATH="$PATH" OLD_HOME="${HOME:-}"
PATH=/usr/bin:/bin HOME="$TMP/home" BBLAB_TOOL_PATH=""
bootstrap_tool_path
assert_eq "$TMP/home/go/bin/fake-bblab-tool" "$(command -v fake-bblab-tool)" "systemd PATH bootstrap"
require_tools fake-bblab-tool
if require_tools definitely-not-a-real-bblab-tool >/dev/null 2>&1; then
  fail "preflight aceitou tool ausente"
fi
pass=$((pass + 2))
PATH="$OLD_PATH" HOME="$OLD_HOME"

mkdir -p "$TMP/state"
for _ in $(seq 1 10); do
  BBLAB_STATE_DIR="$TMP/state" python3 "$ROOT/bin/state.py" delta concurrent 0 >/dev/null &
done
wait
assert_eq "4.0" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["boost"])' "$TMP/state/concurrent.json")" \
  "atomic concurrent state updates"

printf 'OK: %d testes de regressao\n' "$pass"
