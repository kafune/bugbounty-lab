# Como usar este lab

Fluxo mental (fundação shuvonsec): **Recon → Learn → Hunt → Validate → Report**,
com o 7-Question Gate matando achado fraco antes de reportar.

A tua skill **`h1-program-kickoff`** é o runbook Day-0 concreto (7 fases) que aterrissa
esse fluxo. O repo automatiza as partes mecânicas dela:

| Fase do kickoff | O que é | Como rodar aqui |
|---|---|---|
| P0 — Rules of engagement | atribuição + limites de escopo | leia a policy; `export H1USER=...` |
| P1 — Workspace + scope | parse de escopo | **`make sync HANDLE=<prog>`** (automatizado) |
| (ponte) | subs/hosts vivos | **`make recon PROG=<prog>`** |
| P2 — Provided creds ⭐ | Postman/token fornecido | `postman-auth.py <coll> --mint` |
| P3 — Fingerprint | classifica cada host | `fingerprint.sh loot/<prog>/live-urls.txt` |
| P4 — JS + sourcemaps | superfície nos bundles | `js-mine.sh` + `sourcemap.py` |
| P5 — API + authz | BOLA/IDOR/tenant | manual + `hunt-*` da fundação (+ refs em `playbook/refs/anthropic-cyber-skills/`) |
| P6 — Cloud misconfig | Firebase/GCS/OAuth | `firebase-storage.sh` |
| P7 — Validate & record | FINDINGS.md + gate | `triage-validation` da fundação |

Detalhe de cada fase, assinaturas de backend e tabela de roteamento pras `hunt-*`:
`skills/custom/h1-program-kickoff/SKILL.md`.

---

## Onde colocar o que é seu
- Skill nova de classe/técnica -> `skills/custom/<nome>/SKILL.md`
- Ajuste que sobrepõe algo da fundação -> `skills/overrides/`
- Automação/tooling de nível repo -> `bin/`
- Scripts que pertencem a uma skill -> junto dela, em `skills/custom/<skill>/scripts/`
- Referência técnica externa (payloads/checklists de terceiros) -> `playbook/refs/<fonte>/`.
  Já há `anthropic-cyber-skills/` (Tier 1 web/API, Apache-2.0). Roteamento por classe:
  tabela em `skills/custom/h1-program-kickoff/SKILL.md` (coluna "Ref local").
