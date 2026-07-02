---
description: "Dashboard dos achados entre todos os programas: contagem por status, bounty somado. Uso: /status"
---

# /status

Visão geral do funil de achados.

## Passos

1. Rode `make status` (equivale a `bin/findings.py summary`).
2. Apresente: total por status (`triaging/confirmed/reported/dup/negative/paid`), bounty acumulado,
   e destaque o que está `confirmed` mas ainda não `reported` (fila de report) e o que está
   `reported` aguardando (fila de bounty).
3. Se o usuário pedir detalhe de um programa: `bin/findings.py list <handle>`.
