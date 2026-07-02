---
description: "Re-roda recon e mostra só o que é NOVO desde o último baseline (subdomínio/url/nuclei). Uso: /monitor <handle>  (ou sem arg = todos)"
---

# /monitor <handle>

Monitoramento contínuo: detecta mudança de superfície — onde nascem os bugs de bounty.

## Passos

1. Rode `make monitor PROG=<handle>` (ou `make monitor-all` se nenhum handle for dado).
2. Leia os deltas em `loot/<handle>/new-*-{subs,urls,nuclei}.txt`.
3. **Resuma pro usuário só o que é novo e acionável**: subdomínios novos (candidatos a takeover /
   nova app), URLs/endpoints novos, hits de nuclei. Ignore ruído.
4. Para cada delta interessante, proponha o próximo passo (fingerprint, JS-mine, hunt-* específica)
   — sempre validando escopo com `bin/scope-check.sh` antes de tocar.

O `monitor.sh` já filtra por escopo e dispara `bin/notify.sh` se houver delta e webhook configurado.
