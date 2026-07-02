---
description: "Valida se um host está in-scope (e não out-of-scope) de um programa ANTES de tocar nele. Uso: /scope-check <host> <handle>"
---

# /scope-check <host> <handle>

Pré-flight de segurança. Use SEMPRE antes de sondar um host manualmente.

## Passos

1. Rode `bash bin/scope-check.sh <host> <handle>`.
2. Exit `0` = in-scope, pode prosseguir. Exit `1` = fora de escopo (ou em out-of-scope) → **PARE**,
   não toque no host, avise o usuário.

Regra dura do lab: nada de sonda contra host que não passe neste check. Ver `CLAUDE.md`.
