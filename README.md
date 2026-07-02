# bugbounty-lab

Setup de bug bounty montado sobre a fundação **[shuvonsec/claude-bug-bounty](https://github.com/shuvonsec/claude-bug-bounty)** (metodologia, 7-Question Gate, slash commands `/recon /hunt /validate /report`), com uma camada própria de automação por cima:

- **`bin/h1sync.py`** — puxa programas + escopo estruturado da API do HackerOne e materializa um `scope.txt` por programa em `targets/`.
- **`bin/recon.sh`** — wrapper de recon com **trava de escopo**: só sonda o que está in-scope, descarta out-of-scope antes de tocar no alvo.
- **`bin/monitor.sh`** — re-roda o recon e mostra **só o delta** (subdomínio/url/nuclei novo) contra um baseline; dispara notificação. É onde saem os bugs de bounty.
- **`bin/notify.sh`** — manda o delta pra Telegram/Discord (webhook opcional no `.env`).
- **`bin/findings.py`** — tracker de achados entre programas (status, severidade, bounty).
- **`CLAUDE.md` + `.claude/`** — fazem o Claude Code pilotar o lab com scope-guard: `/kickoff`, `/monitor`, `/status`, `/scope-check`.

> Para uso exclusivamente em alvos autorizados — programas de bug bounty in-scope, engajamentos com autorização escrita, ou infraestrutura própria. A trava de escopo existe pra isso não vazar.

## Arquitetura

```
bugbounty-lab/
├── CLAUDE.md                     # como o Claude Code opera o lab (scope-guard, fluxo)
├── .claude/                      # settings + slash-commands: /kickoff /monitor /status /scope-check
├── vendored/claude-bug-bounty/   # FUNDAÇÃO — submodule do shuvonsec. NÃO editar.
├── skills/
│   ├── custom/
│   │   └── h1-program-kickoff/   # runbook Day-0 (7 fases) + scripts/ das fases 2–6
│   └── overrides/                # ajustes que sobrepõem a fundação
├── bin/
│   ├── _scope.sh                 # scope-guard COMPARTILHADO (fonte única)
│   ├── h1sync.py                 # HackerOne API -> scope.txt   (automatiza a Fase 1 do kickoff)
│   ├── recon.sh                  # recon com scope-guard         (ponte Fase 1 -> Fase 3)
│   ├── monitor.sh                # recon + diff contra baseline  (deltas de superfície)
│   ├── notify.sh                 # Telegram/Discord em delta
│   ├── scope-check.sh            # pré-flight: host in-scope? (exit 0/1)
│   ├── findings.py               # tracker de achados entre programas
│   └── h1report.py               # monta/cria report H1 de um findings/*.md (dry-run default)
├── templates/report/             # template de report no formato H1
├── playbook/  docs/OPERATING.md  # o "porquê/quando" — aponta pras skills
├── targets/<handle>/             # 🔒 git-ignored — scope.txt por programa
├── loot/<handle>/                # 🔒 git-ignored — resultados brutos + .baseline/
├── findings/<handle>/            # 🔒 git-ignored — achados rastreados (só _EXAMPLE versionado)
├── configs/                      # 🔒 git-ignored — .conf com chaves
├── setup.sh                      # roda uma vez após clonar
└── Makefile                      # atalhos: make sync / recon / monitor / status
```

A fundação entra como **git submodule**: fica claro que é código do shuvonsec, versão X, e não se mistura com o que é seu. Quando ele atualizar, `git submodule update --remote` e pronto — suas customizações em `skills/` não são tocadas.

## Setup (uma vez)

Pré-requisito (Ubuntu/Debian): `sudo apt install -y python3-venv python3-pip`

```bash
git clone --recursive <este-repo> && cd bugbounty-lab
./setup.sh
# edite .env com H1_USER, H1_TOKEN e H1USER (gere o token em HackerOne > Settings > API Token)
```

O `setup.sh` faz `git init` (se preciso), vincula a fundação como submodule, instala as tools dela, cria o `.env` e monta um **venv** em `.venv/` com as deps Python (`requests`, `pyjwt`, `cryptography`). O `make` usa esse venv automaticamente; pros scripts Python da skill, ative com `source .venv/bin/activate`.

Clonou sem `--recursive`? Rode `git submodule update --init --recursive`.

## Uso diário

```bash
source .env

# 1. escopo (automatiza a Fase 1 do kickoff)
make sync                  # puxa escopo de todos os programas acessíveis
make sync HANDLE=acme      # ou só um

# 2. recon com scope-guard (ponte pra Fase 3)
make recon PROG=acme       # -> loot/acme/live-urls.txt, subs.txt, urls.txt, nuclei.txt

# 3. kickoff — deep work das fases 2–6 (skill h1-program-kickoff)
K=skills/custom/h1-program-kickoff/scripts
bash $K/fingerprint.sh loot/acme/live-urls.txt          # Fase 3: fingerprint + classifica backend
bash $K/js-mine.sh https://app.acme.com                 # Fase 4: bundles + .map + grep de superfície
python3 $K/sourcemap.py <map-url> out_src               # Fase 4: reconstrói source num .map 200
python3 $K/postman-auth.py <collection.json> --mint     # Fase 2: minta token de credencial fornecida
bash $K/firebase-storage.sh <bucket.appspot.com> list   # Fase 6: bucket Firebase
```

O `recon.sh` roda `subfinder → httpx → katana → nuclei`, cada passo **opcional** (tool ausente é pulada, não quebra). Tudo filtrado contra `scope.txt` / `out-of-scope.txt`. Resultado em `loot/<handle>/`.

Para o "porquê/quando" de cada fase e a tabela de roteamento pras `hunt-*` da fundação, veja `skills/custom/h1-program-kickoff/SKILL.md`.

## Monitoramento contínuo (onde saem os bugs)

```bash
make recon PROG=acme       # 1ª run semeia o baseline em loot/acme/.baseline/
make monitor PROG=acme     # re-roda e emite SÓ o novo -> loot/acme/new-<data>-*.txt
make monitor-all           # itera todos os programas em targets/
```

Delta não-vazio dispara `bin/notify.sh` (Telegram/Discord, se configurado no `.env`). Para rodar
sozinho, agende no cron — veja `bin/monitor.cron.example`.

## Rastreio de achados + report

```bash
bin/findings.py new acme idor-transactions   # cria findings/acme/idor-transactions.md do template
make status                                   # dashboard: contagem por status + bounty somado
bin/h1report.py findings/acme/idor-transactions.md            # dry-run: imprime o payload
bin/h1report.py findings/acme/idor-transactions.md --submit   # cria o report no H1
```

Achados ficam em `findings/<handle>/*.md` (git-ignored). Antes de `--submit`, passe pelo
7-Question Gate (`triage-validation` da fundação). Modelo operacional completo em `docs/OPERATING.md`.

## Dirigindo pelo Claude Code

Abra `claude` na raiz e use os slash-commands: `/kickoff <handle>`, `/monitor <handle>`,
`/status`, `/scope-check <host> <handle>`. O `CLAUDE.md` ensina o agente a respeitar a trava de escopo.

## Segurança operacional

- `.env`, `targets/`, `loot/` e `configs/*.conf` são **git-ignored**. Nunca commite escopo de programa privado, token ou achado.
- Antes de rodar `install_tools.sh` de qualquer repo vendored, revise o conteúdo. Você não quer ser o vetor.
