#!/usr/bin/env bash
#
# install.sh — instala os systemd timers do loop contínuo.
# Substitui __BBLAB_ROOT__/__BBLAB_USER__ nos templates, copia pra
# /etc/systemd/system, faz daemon-reload e enable --now dos 3 timers.
#
# Uso:
#   bash deploy/systemd/install.sh                 # usuário = quem invocou
#   BBLAB_USER=bbhunter bash deploy/systemd/install.sh
#   BBLAB_DRYRUN=1 bash deploy/systemd/install.sh  # só imprime, não instala
#
# Requer privilégio pra escrever em /etc/systemd/system (roda sudo se preciso).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
USER_RUN="${BBLAB_USER:-${SUDO_USER:-$(id -un)}}"
DEST="/etc/systemd/system"
DRY="${BBLAB_DRYRUN:-}"

if [ "$USER_RUN" = "root" ]; then
  echo "recusando rodar o loop como root — defina BBLAB_USER=<usuário não-root>" >&2
  exit 1
fi
if ! id -u "$USER_RUN" >/dev/null 2>&1; then
  msg="usuário '$USER_RUN' não existe. Crie antes: sudo useradd -m -s /bin/bash $USER_RUN"
  if [ -n "$DRY" ]; then echo "[aviso] $msg" >&2; else echo "$msg" >&2; exit 1; fi
fi

SUDO=""
if [ -z "$DRY" ] && [ ! -w "$DEST" ]; then
  SUDO="sudo"
fi

UNITS=(
  bblab-notify-failure@.service
  bblab-tier0.service bblab-tier0.timer
  bblab-tier1.service bblab-tier1.timer
  bblab-tier2.service bblab-tier2.timer
)

echo "ROOT = $ROOT"
echo "USER = $USER_RUN"
echo "DEST = $DEST"
[ -n "$DRY" ] && echo "(dry-run: nada será instalado)"

render() {  # substitui placeholders em STDOUT
  sed -e "s#__BBLAB_ROOT__#$ROOT#g" -e "s#__BBLAB_USER__#$USER_RUN#g" "$1"
}

for u in "${UNITS[@]}"; do
  src="$HERE/$u"
  [ -f "$src" ] || { echo "faltando template: $src" >&2; exit 1; }
  if [ -n "$DRY" ]; then
    echo "=== $u ==="; render "$src"
  else
    render "$src" | $SUDO tee "$DEST/$u" >/dev/null
    echo "instalado: $DEST/$u"
  fi
done

[ -n "$DRY" ] && { echo "dry-run concluído."; exit 0; }

$SUDO systemctl daemon-reload
for t in bblab-tier0.timer bblab-tier1.timer bblab-tier2.timer; do
  $SUDO systemctl enable --now "$t"
  echo "enabled: $t"
done

echo
echo "pronto. Veja: make loop-status"
