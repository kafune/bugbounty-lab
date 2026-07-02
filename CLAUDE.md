# CLAUDE.md — como operar este lab

Framework pessoal de bug bounty para HackerOne. Você (Claude) é o piloto: dirige o fluxo
abaixo conversando comigo, sempre respeitando a **trava de escopo**.

## Regra dura — SCOPE-GUARD (nunca viole)

- **Só toque em host que está em `targets/<handle>/scope.txt` e NÃO está em `out-of-scope.txt`.**
  Antes de qualquer sonda/curl/tool contra um alvo, valide com `bash bin/scope-check.sh <host> <handle>`
  (exit 0 = pode; exit 1 = pare).
- Wildcards (`*.dominio`) autorizam subdomínios daquela raiz; nunca extrapole a raiz.
- Mutação para fora (upload/POST/escrita em storage de terceiro, ex. Firebase write) é **outward mutation**:
  peça confirmação explícita ao usuário antes, use nome único, tente limpar depois.
- Classes fora de escopo da policy (CSP best-practice, cookie flags, clickjacking sem ação, DoS,
  rate-limit unauth, open-redirect sem impacto) não valem sessão — pule.

## Fluxo (fundação shuvonsec): Recon → Learn → Hunt → Validate → Report

O 7-Question Gate (`triage-validation`) mata achado fraco antes de virar report.

## Layout

- `vendored/claude-bug-bounty/` — FUNDAÇÃO (submodule). Skills `bb-methodology`, `hunt-*`,
  `triage-validation`, `report-writing`; tools de recon; MCP de Burp/Caido/H1. **Não editar.**
- `skills/custom/` — skills autorais. A principal é **`h1-program-kickoff`** (runbook Day-0, 7 fases).
- `skills/overrides/` — ajustes que sobrepõem a fundação.
- `bin/` — automação de nível repo (ver tabela abaixo).
- `targets/<handle>/` — escopo por programa (git-ignored). `loot/<handle>/` — resultado bruto.
- `findings/<handle>/` — achados rastreados (git-ignored). `templates/report/` — template de report H1.
- `playbook/` — o "porquê/quando"; aponta pras skills.

## Comandos do lab

| Precisa de | Rode |
|---|---|
| Puxar escopo do H1 | `make sync` · `make sync HANDLE=<h>` |
| Testar auth da API H1 | `make check` |
| Recon com scope-guard (baseline) | `make recon PROG=<h>` |
| Monitorar deltas (novo subdomínio/url/nuclei) | `make monitor PROG=<h>` · `make monitor-all` |
| Validar host antes de tocar | `bash bin/scope-check.sh <host> <h>` |
| Dashboard de achados | `make status` (ou `bin/findings.py summary`) |
| Novo achado do template | `bin/findings.py new <h> <slug>` |

Scripts Python da skill usam o venv (`.venv/`): `source .venv/bin/activate` ou `.venv/bin/python`.

## Quando disparar `h1-program-kickoff`

Assim que eu te entregar o escopo de um programa NOVO ("começa esse programa", "aqui está o escopo",
"novo alvo <x>"). Ela é o runbook Day-0 concreto: parse de escopo, credenciais fornecidas ⭐,
fingerprint→JS/sourcemap→API-auth, cloud quick-wins, roteamento pras `hunt-*`. Detalhe e tabela de
roteamento: `skills/custom/h1-program-kickoff/SKILL.md`. Contexto de fluxo: `playbook/00-como-usar.md`.

## Higiene

`.env`, `targets/`, `loot/`, `findings/` (exceto `_EXAMPLE`) e `configs/*.conf` são git-ignored.
Nunca commite escopo privado, token ou achado. Revise `install_tools.sh` de qualquer vendored antes de rodar.
