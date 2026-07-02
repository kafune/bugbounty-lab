---
description: "Day-0 de um programa H1: sincroniza escopo, roda recon com scope-guard e invoca a skill h1-program-kickoff. Uso: /kickoff <handle>"
---

# /kickoff <handle>

Onboarding completo de um programa novo. `<handle>` é o handle do programa no HackerOne
(ex.: `acme`). Se o usuário colou um escopo em vez de handle, pule o `make sync` e use a skill
diretamente com o texto colado.

## Passos

1. **Escopo** — `make sync HANDLE=<handle>` (materializa `targets/<handle>/scope.txt` + `out-of-scope.txt`).
   Se falhar por auth, oriente `make check`.
2. **Recon baseline** — `make recon PROG=<handle>` (scope-guarded → `loot/<handle>/`). Estabelece o
   baseline pro `/monitor`.
3. **Kickoff** — invoque a skill **`h1-program-kickoff`** e siga as 7 fases sobre o `loot/<handle>/`:
   RoE/atribuição, parse de escopo, **credenciais fornecidas ⭐**, fingerprint, JS/sourcemaps,
   API+authz, cloud quick-wins. Detalhe: `skills/custom/h1-program-kickoff/SKILL.md`.

## Regras
- **Scope-guard**: antes de tocar qualquer host manualmente, `bash bin/scope-check.sh <host> <handle>`.
- Priorize credenciais/material de teste fornecidos na policy (maior ROI) antes de sonda cega.
- Registre leads em `findings/<handle>/` via `bin/findings.py new <handle> <slug>`.
