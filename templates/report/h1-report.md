---
title: "<título curto e específico do bug>"
status: triaging        # triaging | confirmed | reported | dup | negative | paid
severity: ""            # none | low | medium | high | critical
cwe: ""                 # ex.: CWE-639 (IDOR)
asset: ""               # host/endpoint in-scope afetado
handle: ""              # handle do programa H1
weakness: ""            # nome da fraqueza (ex.: Insecure Direct Object Reference)
bounty: 0               # valor pago (preenche quando 'paid')
h1_report_id: ""        # id do report no H1 depois de submeter
---

## Summary

<uma ou duas frases: o que é, onde, e o impacto direto. Sem enrolação.>

## Steps to Reproduce

1. …
2. …
3. …

> Requests/responses relevantes (censure tokens). Anexe HAR/prints em Supporting Material.

## Impact

<o que um atacante consegue AGORA (não teórico). Quem é afetado, que dado vaza / que ação indevida.>

## Remediation

<correção concreta e específica ao caso.>

## Supporting Material

- <arquivos, prints, PoC script, vídeo>

<!--
Antes de mudar status para 'reported', passe pelo 7-Question Gate (skill triage-validation
da fundação). Mate o que falhar. Severidade honesta: dev/UAT + dado fictício reduz impacto;
separe o PROVADO do INFERIDO.
-->
