#!/usr/bin/env bash
#
# notify.sh — manda uma mensagem pra Telegram e/ou Discord.
# No-op silencioso se nenhum webhook estiver configurado no ambiente (.env).
#
# Uso:
#   bash bin/notify.sh "mensagem"
#   echo "mensagem" | bash bin/notify.sh          # lê de STDIN se sem arg
#
# Config (via .env / ambiente):
#   TG_BOT_TOKEN + TG_CHAT_ID   -> Telegram
#   DISCORD_WEBHOOK             -> Discord
set -uo pipefail

MSG="${1:-}"
[ -z "$MSG" ] && MSG="$(cat)"          # sem arg: lê STDIN
[ -z "$MSG" ] && exit 0                # nada a mandar

have() { command -v "$1" >/dev/null 2>&1; }
have curl || { echo "[notify] curl ausente — pulando" >&2; exit 0; }

sent=0

# --- Telegram ---------------------------------------------------------------
if [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
  curl -s -o /dev/null --max-time 15 \
    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${MSG}" \
    --data-urlencode "disable_web_page_preview=true" && sent=1
fi

# --- Discord ----------------------------------------------------------------
if [ -n "${DISCORD_WEBHOOK:-}" ]; then
  # Discord espera JSON; escapa aspas e quebras de linha.
  esc="$(printf '%s' "$MSG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)"
  [ -z "$esc" ] && esc="\"$(printf '%s' "$MSG" | tr '\n' ' ' | sed 's/"/\\"/g')\""
  curl -s -o /dev/null --max-time 15 -H "Content-Type: application/json" \
    -d "{\"content\": ${esc}}" "$DISCORD_WEBHOOK" && sent=1
fi

[ "$sent" -eq 1 ] || { echo "[notify] nenhum webhook configurado — mensagem não enviada" >&2; exit 0; }
