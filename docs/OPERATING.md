# Modelo operacional do lab

O "porquê/quando" por trás dos comandos. Para o passo-a-passo de um programa novo, veja
`skills/custom/h1-program-kickoff/SKILL.md`; para o mapa de fases, `playbook/00-como-usar.md`.

O Tier 2 automatizado executa Nuclei em lotes, usa detecção de tecnologia para selecionar
templates e por padrão só reporta `medium,high,critical` (info/low são ruído raro de virar
report). Se um lote estoura o timeout, os achados parciais já gravados são preservados — a
próxima run re-escaneia os alvos e o baseline diff pega o que faltou; só um erro real do Nuclei
descarta o resultado. Tamanho de lote, timeout e severidades são configuráveis no `.env`.

## O ciclo fechado

```
   sync            recon            monitor            hunt              findings          report
 (escopo)  ->   (baseline)  ->   (deltas 24/7)  ->  (skills hunt-*) -> (tracker) ->  (h1report)
    |               |                 |                  |                 |              |
 targets/        loot/            loot/new-*        FINDINGS.md/      findings/      HackerOne
```

Cada seta é um comando/skill do lab. O agente (Claude Code) dirige, sempre respeitando o
**scope-guard** (`CLAUDE.md`).

## Quando usar o quê

| Situação | Ação |
|---|---|
| Programa novo, tenho o handle | `/kickoff <handle>` (sync + recon + skill) |
| Programa novo, colaram o escopo | invoque `h1-program-kickoff` com o texto |
| Já tenho baseline, quero saber o que mudou | `/monitor <handle>` — deltas de superfície |
| Vou tocar num host/URL manualmente | `bash bin/scope-check.sh <host-ou-url> <handle>` ANTES |
| Achei algo | `bin/findings.py new <handle> <slug>` e preencha |
| Quero ver meu funil | `/status` |
| Confirmei e passei no 7-Q Gate | `bin/h1report.py findings/<h>/<slug>.md` (dry-run → `--submit`) |

## Por que monitoramento contínuo é o coração

A maioria dos bugs de bounty de programas maduros não está na primeira varredura — está na
**mudança**: um subdomínio novo que subiu sem hardening, um bundle JS novo que vazou endpoint,
um host que voltou a responder. `make monitor` roda o mesmo recon scope-guarded e mostra só o
delta (via `anew` contra `loot/<h>/.baseline/`). Agende no cron (`bin/monitor.cron.example`) e
deixe a notificação (`bin/notify.sh`) te chamar quando algo nascer.

## Disciplina de escopo (não-negociável)

Todo caminho até um alvo passa pela mesma lib: `bin/_scope.sh`. `recon.sh`, `monitor.sh` e
`scope-check.sh` dão `source` nela — uma fonte única, sem divergência. Wildcard autoriza
subdomínio da raiz; out-of-scope sempre subtrai. Se um host não passa no `host_in_scope`, não
existe pro lab.
Para ativos ou exclusoes limitados a caminho, valide a URL completa; validar apenas o hostname
nao comprova que o path pretendido esta autorizado.

## Honestidade de achado

Negativo bem documentado vale (não re-caminha e protege sua validity ratio no H1). Antes de
qualquer `status: reported`, rode a skill `triage-validation` (7-Question Gate) da fundação.
Severidade honesta: dev/UAT + dado fictício reduz impacto; separe o PROVADO do INFERIDO.
