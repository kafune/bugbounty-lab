#!/usr/bin/env bash
#
# _scope.sh - wrappers compartilhados de escopo e helpers do lab.
# E apenas para `source`; o parser estruturado vive em scope_guard.py.

SCOPE_GUARD_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scope_guard.py"

# --- helpers de log ---------------------------------------------------------
have()  { command -v "$1" >/dev/null 2>&1; }
log()   { echo -e "\033[1;34m[*]\033[0m $*"; }
skip()  { echo -e "\033[1;33m[skip]\033[0m $1 nao instalado - passo pulado"; }
ok()    { echo -e "\033[1;32m[done]\033[0m $*"; }
error() { echo -e "\033[1;31m[erro]\033[0m $*" >&2; }

# systemd usa um PATH minimo e nao carrega .profile. As tools Go instaladas
# pelo setup ficam normalmente em ~/go/bin; BBLAB_TOOL_PATH permite override.
bootstrap_tool_path() {
  local extra="${BBLAB_TOOL_PATH:-}"
  if [ -n "${HOME:-}" ]; then
    extra="${extra:+$extra:}$HOME/go/bin:$HOME/.local/bin"
  fi
  export PATH="${extra:+$extra:}$PATH"
}

require_tools() {
  local tool missing=()
  for tool in "$@"; do
    have "$tool" || missing+=("$tool")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    error "tools obrigatorias ausentes do PATH: ${missing[*]}"
    error "PATH=$PATH"
    return 1
  fi
}

scope_roots() {
  if [ "$#" -gt 1 ]; then python3 "$SCOPE_GUARD_PY" roots "$1" "$2"
  else python3 "$SCOPE_GUARD_PY" roots "$1"
  fi
}
scope_enum_roots() {
  if [ "$#" -gt 1 ]; then python3 "$SCOPE_GUARD_PY" enum-roots "$1" "$2"
  else python3 "$SCOPE_GUARD_PY" enum-roots "$1"
  fi
}
scope_seeds()      { python3 "$SCOPE_GUARD_PY" seeds "$1"; }

host_in_scope() {
  python3 "$SCOPE_GUARD_PY" check "$1" "$2" "$3"
}

# Filtra stdin preservando a linha original. O primeiro campo deve ser host/URL.
scope_filter() {
  python3 "$SCOPE_GUARD_PY" filter "$1" "$2"
}

# Uma transferencia valida contem ao menos o SOA da zona no answer section.
axfr_has_soa() {
  awk '$4 == "SOA" { found=1 } END { exit !found }'
}
