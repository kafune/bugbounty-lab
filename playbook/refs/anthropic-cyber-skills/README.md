# Referências técnicas — Anthropic-Cybersecurity-Skills (Tier 1 + 2 + 3)

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

## Conteúdo — Tier 1 (19 refs)

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

## Conteúdo — Tier 2 (17 refs)

### Auth / token (JWT, OAuth)
- `testing-jwt-token-security.md`
- `exploiting-jwt-algorithm-confusion-attack.md`
- `performing-jwt-none-algorithm-attack.md`
- `exploiting-oauth-misconfiguration.md`
- `testing-oauth2-implementation-flaws.md`

### GraphQL
- `performing-graphql-introspection-attack.md`
- `performing-graphql-security-assessment.md`

### XSS
- `testing-for-xss-vulnerabilities.md`
- `testing-for-xss-vulnerabilities-with-burpsuite.md`

### SQL / NoSQL injection
- `exploiting-sql-injection-vulnerabilities.md`
- `exploiting-sql-injection-with-sqlmap.md`
- `performing-second-order-sql-injection.md`
- `exploiting-nosql-injection-vulnerabilities.md`

### Outros (WebSocket, type juggling, traversal, broken-link)
- `exploiting-websocket-vulnerabilities.md`
- `exploiting-type-juggling-vulnerabilities.md`
- `performing-directory-traversal-testing.md`
- `exploiting-broken-link-hijacking.md`

## Conteúdo — Tier 3 (3 refs, recon)

Fonte das técnicas destiladas no `bin/recon.sh` (crt.sh, registros DNS + AXFR,
URLs históricas via gau/waybackurls). Os docs ficam como referência do "porquê".

- `performing-subdomain-enumeration-with-subfinder.md`
- `performing-dns-enumeration-and-zone-transfer.md`
- `conducting-external-reconnaissance-with-osint.md`

## Procedência e atualização

Baixados de `raw.githubusercontent.com/mukul975/Anthropic-Cybersecurity-Skills/main/skills/<slug>/SKILL.md`.
Para atualizar, rebaixe os mesmos slugs e reinjete o banner. Pack completo: 39 refs
(19 Tier 1 + 17 Tier 2 + 3 Tier 3). Ideias ainda não portadas p/ `recon.sh` (rodar à mão):
DNS brute-force com wordlist (puredns/shuffledns), Shodan/Censys, cloud-bucket enum.
