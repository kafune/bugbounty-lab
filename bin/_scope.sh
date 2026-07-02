#!/usr/bin/env bash
#
# _scope.sh — biblioteca de scope-guard COMPARTILHADA.
# Fonte única da lógica de escopo usada por recon.sh, monitor.sh e scope-check.sh.
# É só para `source` — não executa nada ao ser carregada.
#
# Uso:
#   source "$(dirname "$0")/_scope.sh"
#   scope_roots      <scope.txt>                 -> imprime raízes (wildcard -> raiz)
#   scope_oos_regex  <out-of-scope.txt>          -> imprime regex de out-of-scope
#   scope_filter     <roots.txt> <oos_regex>     -> filtra STDIN (mantém in-scope)
#   host_in_scope    <host> <scope.txt> <oos.txt> -> exit 0 se in-scope, 1 se não

# --- helpers de log (compartilhados) ----------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
log()  { echo -e "\033[1;34m[*]\033[0m $*"; }
skip() { echo -e "\033[1;33m[skip]\033[0m $1 não instalado — passo pulado"; }
ok()   { echo -e "\033[1;32m[done]\033[0m $*"; }

# raízes in-scope: extrai domínios, tira o prefixo de wildcard, dedup.
scope_roots() {
  grep -oE '([a-zA-Z0-9*_-]+\.)+[a-zA-Z]{2,}' "$1" 2>/dev/null \
    | sed 's/^\*\.//' | sort -u
}

# regex de out-of-scope. Se vazio/ausente, devolve um regex que nunca casa ($^).
scope_oos_regex() {
  if [ -f "$1" ] && [ -s "$1" ]; then
    sed 's/^\*\.//; s/\./\\./g' "$1" | paste -sd'|' -
  else
    echo '$^'
  fi
}

# Filtra STDIN: mantém só o que casa uma raiz in-scope (o próprio domínio ou
# subdomínio dele) E não casa out-of-scope. Args: <roots.txt> <oos_regex>.
scope_filter() {
  local roots="$1" oos_re="$2"
  grep -E -f <(sed 's/\./\\./g; s/^/(^|\.)/; s/$/$/' "$roots") \
    | grep -vE "$oos_re" || true
}

# Testa um único host. Extrai o hostname de uma URL se vier com esquema/porta.
# Exit 0 = in-scope; 1 = fora.
host_in_scope() {
  local host="$1" scope="$2" oos="$3"
  host="${host#*://}"; host="${host%%/*}"; host="${host%%:*}"
  [ -n "$host" ] && [ -f "$scope" ] || return 1
  local roots oos_re match
  roots="$(mktemp)"; scope_roots "$scope" > "$roots"
  oos_re="$(scope_oos_regex "$oos")"
  match="$(printf '%s\n' "$host" | scope_filter "$roots" "$oos_re")"
  rm -f "$roots"
  [ -n "$match" ]
}
