#!/usr/bin/env bash
#
# setup.sh — prepara o lab. Roda uma vez após clonar.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "[*] Garantindo repositório git..."
[ -d .git ] || { git init -q && echo "    git init feito"; }

echo "[*] Vinculando a fundação (shuvonsec/claude-bug-bounty) como submodule..."
if [ ! -e vendored/claude-bug-bounty/.git ]; then
  rmdir vendored/claude-bug-bounty 2>/dev/null || true
  git submodule add https://github.com/shuvonsec/claude-bug-bounty vendored/claude-bug-bounty || \
    echo "    (submodule já existe ou falhou — revise manualmente)"
fi
git submodule update --init --recursive || true

echo "[*] Instalando as tools da fundação (subfinder, httpx, nuclei, katana, ffuf...)"
if [ -f vendored/claude-bug-bounty/install_tools.sh ]; then
  ( cd vendored/claude-bug-bounty && bash install_tools.sh ) || \
    echo "    revise vendored/claude-bug-bounty/install_tools.sh manualmente"
fi

echo "[*] Criando .env a partir do exemplo (se ainda não existe)..."
[ -f .env ] || cp .env.example .env

echo "[*] Configurando venv Python (.venv/)..."
if python3 -m venv .venv 2>/dev/null; then
  ./.venv/bin/python -m pip install --quiet --upgrade pip
  ./.venv/bin/python -m pip install --quiet -r requirements.txt
  [ -f vendored/claude-bug-bounty/requirements.txt ] && \
    ./.venv/bin/python -m pip install --quiet -r vendored/claude-bug-bounty/requirements.txt
  echo "    venv pronto (requests, pyjwt, cryptography + deps da fundação)"
else
  echo "    [!] venv indisponível. Instale e rode de novo:"
  echo "        sudo apt install -y python3-venv python3-pip"
fi

echo
echo "[done] Agora:"
echo "  1. edite .env com H1_USER, H1_TOKEN e H1USER"
echo "  2. source .env && make sync        # puxa escopo do HackerOne"
echo "  3. make recon PROG=<handle>        # roda recon do programa"
echo
echo "  (scripts Python da skill usam o venv: 'source .venv/bin/activate' antes,"
echo "   ou chame '.venv/bin/python skills/custom/h1-program-kickoff/scripts/...')"
