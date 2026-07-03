# EXAMPLE — um engajamento de ponta a ponta

Walkthrough de um caça completo num programa **fictício**, do escopo ao report,
usando o tooling real deste lab. Tudo aqui é inventado (domínios, tokens, IDs);
serve como mapa de "como um dia de trabalho flui" respeitando a **trava de escopo**.

> ⚠️ Programa, hosts, credenciais e achados são **fictícios**. Nada aqui foi testado
> contra alvo real. O objetivo é didático: mostrar o fluxo
> **Recon → Learn → Hunt → Validate → Report** com o SCOPE-GUARD no centro.

**Alvo fictício:** `Acme Pay` — fintech de pagamentos.
**Plataforma:** HackerOne, handle `acmepay` (no fim há a variação p/ Bugcrowd).

---

## Fase 0 — Rules of engagement (leia a policy ANTES de tocar em nada)

Escopo que o programa publicou (colado da policy do H1):

```
In scope:
  *.acmepay.io           (wildcard — web + APIs)
  acmepay.com            (site institucional)
  Acme Pay Android app   (com.acmepay.wallet)
Out of scope:
  blog.acmepay.io        (WordPress gerenciado por terceiro)
  status.acmepay.io      (statuspage.io)
  *.uat.acmepay.io       (ambiente de terceiro — NÃO testar)
Max severity: Critical
Excluded classes: CSP best-practice, cookie flags, clickjacking sem PoC,
  rate-limit unauth, open-redirect sem impacto, DoS, self-XSS.
Provided creds: Postman collection com 2 usuários de teste (tenant A e B).
```

Três coisas que já mudam o jogo, anotadas antes de qualquer sonda:

1. **`*.uat.acmepay.io` é OUT-OF-SCOPE** apesar de casar o wildcard `*.acmepay.io`.
   Isso vai pro `out-of-scope.txt` e o scope-guard vai barrar sozinho.
2. **Creds de teste fornecidas ⭐** (dois tenants) — ouro pra caçar BOLA/IDOR autenticado.
   É a fase P2 do kickoff.
3. **Classes excluídas** — não gasto sessão em open-redirect, CSP, DoS, etc.

---

## Fase 1 — Workspace + escopo (`make sync`)

```bash
make sync HANDLE=acmepay
```

Isso puxa o escopo do H1 e materializa:

```
targets/acmepay/scope.txt          # *.acmepay.io, acmepay.com
targets/acmepay/out-of-scope.txt   # blog.acmepay.io, status.acmepay.io, *.uat.acmepay.io
```

**Confiro a trava antes de tudo** — o host UAT tem que ser barrado:

```bash
$ bash bin/scope-check.sh api.uat.acmepay.io acmepay
[out-of-scope] api.uat.acmepay.io  -> exit 1   # ✋ o guard funciona

$ bash bin/scope-check.sh api.acmepay.io acmepay
[in-scope] api.acmepay.io          -> exit 0   # ✓ pode tocar
```

Regra que eu (Claude) sigo o engajamento inteiro: **antes de qualquer curl/tool contra
um host, `scope-check` tem que dar exit 0.** UAT nunca é tocado, nem por engano.

---

## Fase 1.5 — Recon com scope-guard (`make recon`)

```bash
make recon PROG=acmepay
```

Pipeline (cada tool é opcional; tudo re-filtrado por escopo):

```
[*] programa: acmepay
[*] raízes in-scope: 2
[*] subfinder...                      subs passivos
[*] crt.sh (cert transparency)...     +subs de certificados
[*] DNS records + AXFR...             NS/MX/TXT + tentativa de zone transfer
[*] subs (multi-fonte): 37
[*] httpx (probe + tech)...           vivos: 19
[*] katana (crawl)...                 +
[*] gau (wayback histórico)...        urls (crawl+histórico): 2.481
[*] nuclei (info,low,medium)...       achados nuclei: 6
[done] recon de 'acmepay' concluído.
```

Resultado bruto em `loot/acmepay/`:

```
roots.txt  subs.txt  live.txt  live-urls.txt  urls.txt  nuclei.txt  dns/
```

O que o multi-fonte pescou que o subfinder sozinho não tinha:

- **crt.sh** revelou `admin-legacy.acmepay.io` (certificado emitido, host esquecido).
- **gau** trouxe `/api/v1/internal/export?debug=1` de uma versão antiga (Wayback).
- **AXFR** falhou (fechado) — esperado; se tivesse aberto viraria finding sozinho
  em `loot/acmepay/dns/axfr.txt`.

> Nota de escopo: `blog.acmepay.io` apareceu no crt.sh mas foi **descartado**
> pelo `in_scope_filter` antes de qualquer probe — está no out-of-scope.

---

## Fase 2 — Provided creds ⭐ (o atalho que a maioria ignora)

A policy deu uma Postman collection. Extraio o token de teste dos dois tenants:

```bash
.venv/bin/python skills/custom/h1-program-kickoff/scripts/postman-auth.py \
  loot/acmepay/acmepay.postman_collection.json --mint
# tenant A: eyJhbGciOi...  (user alice@securitylab, tenantId=TA-1001)
# tenant B: eyJhbGciOi...  (user bob@securitylab,   tenantId=TB-2002)
```

Dois tenants autenticados = setup perfeito pra testar **isolamento multi-tenant (BOLA)**,
que é a classe que mais paga em fintech.

---

## Fase 3–4 — Fingerprint → JS/sourcemaps

Classifico cada host vivo e minero os bundles:

```bash
bash skills/custom/h1-program-kickoff/scripts/fingerprint.sh loot/acmepay/live-urls.txt
# api.acmepay.io      -> JSON API (Kong gateway, backend Node)
# app.acmepay.io      -> SPA React (tem sourcemaps!)
# admin-legacy.acmepay.io -> 200, Basic-auth prompt (interessante)

bash skills/custom/h1-program-kickoff/scripts/js-mine.sh app.acmepay.io
.venv/bin/python skills/custom/h1-program-kickoff/scripts/sourcemap.py app.acmepay.io
```

O sourcemap do SPA (`webpack://acmepay-app/...`) expôs o **contrato da API interna**,
incluindo uma rota com cheiro de BOLA:

```
POST /client/v1/transactions/list   body: { "companies": ["<companyId>"] }
```

Aponto isso pras refs de autorização (routing table do kickoff):
`playbook/refs/anthropic-cyber-skills/testing-api-for-broken-object-level-authorization.md`.

---

## Fase 5 — Hunt: BOLA/IDOR (o achado que vale)

Sigo o checklist da ref de BOLA. Como **tenant A**, listo minhas companies e pego um ID:

```bash
TA="eyJhbGciOi..."   # token tenant A
# baseline: minhas próprias companies
curl -s https://api.acmepay.io/client/v1/companies \
  -H "Authorization: Bearer $TA" | jq '.[].id'
# "CMP-A-777"
```

Como **tenant B**, descubro um companyId do B (`CMP-B-909`). Agora o teste-chave:
com o token do **A**, peço as transações da company do **B**:

```bash
curl -s https://api.acmepay.io/client/v1/transactions/list \
  -H "Authorization: Bearer $TA" \
  -H "Content-Type: application/json" \
  -d '{"companies":["CMP-B-909"]}'
```

Resposta **200** com transações do tenant B:

```json
{ "items": [
  { "id":"TX-55021", "company":"CMP-B-909", "amount":18450.00,
    "counterparty":"ACME SUPPLIERS LTDA", "payerDoc":"***.***.891-**" }
]}
```

⛔ O servidor **não valida** se as `companies[]` pertencem ao tenant do token.
Confirmo com a Autorize (Burp) rodando A-vs-B em toda a superfície: 3 endpoints afetados.

**Isolamento multi-tenant quebrado** — um cliente lê dados financeiros de outro. Money class.

---

## Fase 5b — o que NÃO virou report (o 7-Question Gate matando achado fraco)

No mesmo dia achei também:

- **`admin-legacy.acmepay.io` com Basic-auth** → tentei defaults, nada. Sem bypass, sem
  impacto demonstrável. **Morto** (Q: "consigo provar impacto AGORA?" → não).
- **Open-redirect em `/logout?next=`** → a policy exclui *open-redirect sem impacto* e não
  consegui encadear em roubo de token. **Pulado** (fora de escopo de classe).
- **Header CSP fraco** no `app.` → *CSP best-practice* é classe excluída. **Pulado.**

O gate (`triage-validation` da fundação) existe pra isso: só sobe o que passa nas 7 perguntas.
Severidade honesta — separo o **provado** (leitura cross-tenant, com request/response) do
**inferido** (possível escrita? não testei mutação sem autorização do usuário).

---

## Fase 6 — Cloud quick-wins (rápido, mas nada aqui)

```bash
bash skills/custom/h1-program-kickoff/scripts/firebase-storage.sh \
  acmepay-prod.appspot.com list          # 403 — fechado, ok
```

Buckets fechados. Sigo com o achado forte que já tenho.

---

## Fase 7 — Validate & record (`findings.py` + template)

Materializo o achado a partir do template rastreável:

```bash
bin/findings.py new acmepay bola-transactions-cross-tenant
# criado: findings/acmepay/bola-transactions-cross-tenant.md
```

Preencho o frontmatter e as seções (mesmo formato de `findings/_EXAMPLE/example.md`):

```markdown
---
title: "BOLA em /client/v1/transactions/list vaza transações de outro tenant"
status: confirmed
severity: high
cwe: CWE-639
asset: api.acmepay.io
handle: acmepay
weakness: "Broken Object Level Authorization"
bounty: 0
h1_report_id: ""
---

## Summary
O endpoint `POST /client/v1/transactions/list` aceita um array `companies[]`
controlado pelo cliente e não valida se as companies pertencem ao tenant do token,
vazando transações (valores, contrapartes, PII parcial) de tenants arbitrários.

## Steps to Reproduce
1. Autentique como tenant A (token de teste fornecido).
2. Obtenha um companyId do tenant B (`CMP-B-909`).
3. `POST /client/v1/transactions/list` com `{"companies":["CMP-B-909"]}` usando o token de A.
4. Resposta 200 retorna transações do tenant B.

## Impact
Qualquer cliente autenticado lê dados financeiros de outros tenants — quebra de
isolamento multi-tenant. Afeta toda a base; expõe valores, contrapartes e PII parcial.

## Remediation
Validar server-side que cada `companyId` do array pertence ao tenant do token
(checagem de ownership no nível de objeto) antes de retornar dados.

## Supporting Material
- request/response A→B (tokens censurados), captura da Autorize, PoC curl.
```

Dashboard atualiza sozinho:

```bash
$ make status
acmepay   confirmed:1  triaging:0  reported:0  paid:0   bounty: $0
```

---

## Fase 8 — Report

O `.md` do finding **é** o corpo do report H1 (template já espelha os campos do H1).
Antes de mudar `status: confirmed → reported`, última passada no 7-Question Gate.
Submeto no HackerOne, colo o `h1_report_id` de volta no frontmatter, e sigo o monitor:

```bash
make monitor PROG=acmepay    # avisa se surgir subdomínio/url/nuclei novo depois
```

---

## Variação Bugcrowd

O fluxo é idêntico; muda a papelada de escopo e atribuição:

| H1 | Bugcrowd |
|---|---|
| `make sync HANDLE=<h>` (API H1) | escopo colado do *Brief* → `targets/<h>/scope.txt` à mão |
| Reputação/Signal | VRT (Vulnerability Rating Taxonomy) define severidade |
| Report = template `h1-report.md` | mesmo `.md`; mapeie severidade pra **VRT**, não CVSS livre |
| Atribuição via headers da policy | Bugcrowd costuma exigir header `Bugcrowd-<researcher>` — cheque o Brief |

O SCOPE-GUARD, o recon multi-fonte e o gate de validação valem igual — só a
origem do `scope.txt` e o vocabulário de severidade mudam.

---

## TL;DR do fluxo

```
Fase 0  policy + classes excluídas          (ler ANTES)
Fase 1  make sync + scope-check              (materializa e trava escopo)
Fase 1.5 make recon                          (subfinder+crt.sh+AXFR+gau, scope-filtered)
Fase 2  provided creds ⭐                     (2 tenants = caça BOLA)
Fase 3-4 fingerprint → JS/sourcemap          (contrato da API vaza a rota)
Fase 5  hunt BOLA/IDOR                        (refs Tier 1) → achado forte
Fase 5b 7-Question Gate                       (mata Basic-auth, open-redirect, CSP)
Fase 6  cloud quick-wins                      (buckets fechados)
Fase 7  findings.py new + template            (rastreável) → make status
Fase 8  report H1/Bugcrowd + make monitor     (submete e vigia deltas)
```

Detalhe de cada fase e a routing table por classe:
`skills/custom/h1-program-kickoff/SKILL.md`. Contexto de fluxo: `playbook/00-como-usar.md`.
