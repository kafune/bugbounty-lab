# Referências técnicas — Anthropic-Cybersecurity-Skills (Tier 1 web/API)

**O que é:** subconjunto curado (Tier 1) de skills web/API do repositório comunitário
[`mukul975/Anthropic-Cybersecurity-Skills`](https://github.com/mukul975/Anthropic-Cybersecurity-Skills)
(**Apache-2.0**, não afiliado à Anthropic). Cada `.md` aqui é o `SKILL.md` original do repo,
com um banner **SCOPE-GUARD** injetado logo após o frontmatter.

**O que NÃO é:** não são skills ativas do lab. São **material de referência** (payloads,
checklists, comandos) para enriquecer as `hunt-*` da fundação `vendored/claude-bug-bounty/`.
Não são carregadas pelo mecanismo de skills e não conhecem a trava de escopo por conta própria —
por isso o banner. **Sempre** valide o host com `bash bin/scope-check.sh <host> <handle>` antes
de aplicar qualquer coisa daqui.

## Regras do lab que continuam valendo

- **SCOPE-GUARD:** só toque em host de `targets/<handle>/scope.txt` que não esteja em `out-of-scope.txt`.
- **Outward mutation** (upload/POST/escrita em storage de terceiro): confirmar com o usuário antes.
- **Classes que não valem sessão H1** (puladas de propósito na curadoria): open-redirect sem impacto,
  CSP best-practice, WAF-bypass unauth, DoS / rate-limit unauth, clickjacking sem ação.

## Conteúdo (19 refs)

### SSRF
- `exploiting-server-side-request-forgery.md`
- `performing-blind-ssrf-exploitation.md`

### Autorização / IDOR / API access control
- `testing-api-for-broken-object-level-authorization.md` (BOLA / API1:2023)
- `exploiting-idor-vulnerabilities.md`
- `exploiting-broken-function-level-authorization.md` (BFLA)
- `testing-for-broken-access-control.md`

### API-specific
- `exploiting-mass-assignment-in-rest-apis.md`
- `exploiting-excessive-data-exposure-in-api.md`
- `exploiting-api-injection-vulnerabilities.md`
- `performing-api-inventory-and-discovery.md`

### Injeção / parsing server-side
- `exploiting-template-injection-vulnerabilities.md` (SSTI)
- `testing-for-xxe-injection-vulnerabilities.md`
- `exploiting-insecure-deserialization.md`
- `exploiting-prototype-pollution-in-javascript.md`

### Protocolo HTTP / cache
- `exploiting-http-request-smuggling.md`
- `performing-web-cache-poisoning-attack.md`
- `performing-http-parameter-pollution-attack.md`

### Lógica
- `exploiting-race-condition-vulnerabilities.md`
- `testing-cors-misconfiguration.md`

## Procedência e atualização

Baixados de `raw.githubusercontent.com/mukul975/Anthropic-Cybersecurity-Skills/main/skills/<slug>/SKILL.md`.
Para atualizar, rebaixe os mesmos slugs e reinjete o banner. Tier 2/3 (JWT/OAuth, GraphQL, XSS,
recon) ficaram de fora desta leva — ver a avaliação no histórico do lab.
