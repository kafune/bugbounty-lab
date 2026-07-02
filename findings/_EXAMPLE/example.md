---
title: "IDOR em /client/v1/transactions permite ler transações de outro tenant"
status: confirmed
severity: high
cwe: CWE-639
asset: api.cadastro.uat.acme.app
handle: _EXAMPLE
weakness: "Insecure Direct Object Reference"
bounty: 0
h1_report_id: ""
---

## Summary

O endpoint `POST /client/v1/transactions/list` aceita um array `companies[]` controlado pelo
cliente e não valida se as companies pertencem ao tenant do token, vazando transações de outros
tenants.

## Steps to Reproduce

1. Autentique com o token de teste fornecido (tenant `securitylab`).
2. `POST /client/v1/transactions/list` com `{"companies": ["<id-de-outro-tenant>"]}`.
3. A resposta 200 retorna transações que não pertencem ao seu tenant.

## Impact

Qualquer cliente autenticado lê transações (valores, contrapartes, PII parcial) de tenants
arbitrários — quebra de isolamento multi-tenant.

## Remediation

Validar server-side que cada id em `companies[]` pertence ao tenant do token antes de consultar.

## Supporting Material

- request/response censurados; PoC em `poc/transactions-idor.sh`

<!-- Exemplo versionado. Achados reais ficam em findings/<handle>/ e são git-ignored. -->
