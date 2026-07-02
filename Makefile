# Atalhos do lab.
# .env é lido pelo SHELL em cada recipe (strip de aspas correto), não pelo make.

# usa o python do venv se existir, senão o do sistema
PY := $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

# carrega .env no shell antes de rodar (funciona com ou sem aspas nos valores)
LOADENV := set -a; [ -f .env ] && . ./.env; set +a;

.PHONY: help sync recon monitor monitor-all status clean venv check

help:
	@echo "make sync                 -> puxa escopo de TODOS os programas do H1"
	@echo "make sync HANDLE=acme     -> puxa escopo de um programa"
	@echo "make recon PROG=acme      -> roda recon do programa (usa scope.txt)"
	@echo "make monitor PROG=acme    -> re-roda recon e mostra só o que é NOVO (diff)"
	@echo "make monitor-all          -> monitora todos os programas em targets/"
	@echo "make status               -> dashboard de achados (todos os programas)"
	@echo "make clean PROG=acme      -> limpa o loot de um programa"
	@echo "make check                -> testa a autenticação na API do H1"
	@echo "make venv                 -> (re)cria .venv e instala requirements"

venv:
	@python3 -m venv .venv && .venv/bin/python -m pip install -q --upgrade pip \
	  && .venv/bin/python -m pip install -q -r requirements.txt \
	  && echo "venv pronto"

check:
	@$(LOADENV) \
	code=$$(curl -s -o /dev/null -w '%{http_code}' -u "$$H1_USER:$$H1_TOKEN" \
	  https://api.hackerone.com/v1/hackers/programs); \
	echo "GET /v1/hackers/programs -> HTTP $$code"; \
	case $$code in \
	  200) echo "auth OK";; \
	  401) echo "401 — H1_USER deve ser seu USERNAME do HackerOne e H1_TOKEN o valor do token (sem aspas)";; \
	  *)   echo "resposta inesperada — cheque rede/credenciais";; \
	esac

sync:
	@$(LOADENV) $(PY) bin/h1sync.py $(if $(HANDLE),--handle $(HANDLE),)

recon:
	@test -n "$(PROG)" || { echo "uso: make recon PROG=<handle>"; exit 1; }
	@$(LOADENV) bash bin/recon.sh $(PROG)

monitor:
	@test -n "$(PROG)" || { echo "uso: make monitor PROG=<handle>"; exit 1; }
	@$(LOADENV) bash bin/monitor.sh $(PROG)

monitor-all:
	@$(LOADENV) bash bin/monitor.sh

status:
	@$(PY) bin/findings.py summary

clean:
	@test -n "$(PROG)" || { echo "uso: make clean PROG=<handle>"; exit 1; }
	@rm -rf loot/$(PROG) && echo "loot/$(PROG) limpo"
