# KICKOFF_PROMPT — cole no Claude pra aplicar o framework num programa

Este é o prompt-mestre pra ligar o piloto (Claude) num programa novo. Preencha o
bloco **`INPUT`**, cole tudo no Claude dentro deste repo, e ele conduz o fluxo
`Recon → Learn → Hunt → Validate → Report` respeitando a trava de escopo.

> Atalho: se já rodou `make sync HANDLE=<h>`, você pode simplesmente usar a skill
> **`/kickoff <handle>`**. Este prompt é a versão explícita/portável (funciona em
> sessão nova, força as regras, e serve quando o escopo veio colado em vez de via API).

---

## Como usar

1. Abra o Claude Code **dentro de `bugbounty-lab/`**.
2. Copie o bloco abaixo (de `===` a `===`), preencha o `INPUT`, cole e envie.
3. Deixe o Claude dirigir; ele para e pergunta em qualquer *outward mutation*.

---

```
===================== COLE A PARTIR DAQUI =====================

Você é o piloto deste lab de bug bounty (leia CLAUDE.md). Vamos iniciar um
programa NOVO. Opere o fluxo Recon → Learn → Hunt → Validate → Report.

## INPUT (eu preencho)
- HANDLE:        <ex.: acmepay>
- PLATAFORMA:    <HackerOne | Bugcrowd | outro>
- ORIGEM_ESCOPO: <"API H1 via make sync" | "colado abaixo" | link da policy>
- ESCOPO (se colado):
    In scope:
      <cole aqui>
    Out of scope:
      <cole aqui>
    Max severity: <...>
    Classes excluídas: <...>
- CREDS_FORNECIDAS: <Postman/token/TestFlight? cole caminho ou "nenhuma">
- FOCO (opcional): <ex.: "priorize BOLA/IDOR e authz em API">

## REGRAS DURAS (nunca viole)
1. SCOPE-GUARD: só toque em host de targets/<HANDLE>/scope.txt que NÃO esteja em
   out-of-scope.txt. Antes de QUALQUER curl/sonda/tool contra um alvo, rode
   `bash bin/scope-check.sh <host> <HANDLE>` e só prossiga com exit 0.
   Wildcard autoriza subdomínios daquela raiz — nunca extrapole a raiz.
2. OUTWARD MUTATION (upload/POST/escrita em storage de terceiro, ex. Firebase write):
   PARE e peça minha confirmação explícita antes; use nome único; tente limpar depois.
3. Classes fora de escopo da policy (CSP best-practice, cookie flags, clickjacking
   sem PoC, DoS, rate-limit unauth, open-redirect sem impacto, self-XSS) NÃO valem
   sessão — pule sem gastar tempo.
4. Nada de tocar em host out-of-scope "só pra confirmar". UAT/terceiros = proibido.

## O QUE FAZER (nesta ordem, me mostrando o resultado de cada passo)
P0. Rules of engagement: parse do escopo. Se ORIGEM_ESCOPO="API H1", rode
    `make sync HANDLE=<HANDLE>`; senão, materialize targets/<HANDLE>/scope.txt e
    out-of-scope.txt a partir do ESCOPO colado. Liste raízes in-scope e as exclusões.
    Prove a trava: rode scope-check num host in-scope (espera exit 0) e num
    out-of-scope (espera exit 1).
P1. Recon com guard: `make recon PROG=<HANDLE>`. Resuma o delta interessante de
    loot/<HANDLE>/ (subs novos via crt.sh, urls históricas via gau, AXFR aberto?,
    achados nuclei). Nada de probe fora do escopo.
P2. Provided creds ⭐: se houver, extraia tokens (postman-auth.py --mint) e me diga
    quantos tenants/perfis temos (setup pra BOLA/IDOR autenticado).
P3-P4. Fingerprint → JS/sourcemaps: classifique os hosts vivos
    (fingerprint.sh) e minere bundles (js-mine.sh + sourcemap.py). Aponte
    rotas/segredos/contratos de API que valham caça.
P5. Hunt: roteie cada superfície pela routing table de
    skills/custom/h1-program-kickoff/SKILL.md e use as refs em
    playbook/refs/anthropic-cyber-skills/ como checklist técnico
    (BOLA/IDOR, SSRF, SSTI, etc.). Respeite o FOCO se eu dei um.
P6. Cloud quick-wins: Firebase/GCS/OAuth misconfig (firebase-storage.sh; WRITE é
    outward mutation → regra 2).
P7. Validate & record: para cada candidato, passe pelo 7-Question Gate
    (triage-validation da fundação). MATE o que não provar impacto AGORA. Para o
    que sobreviver: `bin/findings.py new <HANDLE> <slug>`, preencha o template
    (separe PROVADO de INFERIDO, severidade honesta), e rode `make status`.

## COMO SE COMUNICAR COMIGO
- Antes de cada passo que toca a rede, diga qual host e confirme que passou no
  scope-check.
- Ao fim de cada fase, me dê um resumo curto + a decisão (o que seguir, o que matar).
- Não escreva report final sem passar pelo gate. Não invente impacto.
- Pergunte quando: outward mutation, ambiguidade de escopo, ou credencial que eu
  não forneci mas que abriria uma porta.

Comece pela P0 agora.

===================== COLE ATÉ AQUI =====================
```

---

## Variantes rápidas

- **Só recon/monitor (sem caça):** troque "O QUE FAZER" por "rode só P0→P1 e me
  entregue o mapa de superfície; não faça hunt ainda."
- **Retomar um programa já iniciado:** "o escopo de <HANDLE> já está em targets/;
  rode `make monitor PROG=<HANDLE>` e me diga só o que é NOVO desde o último baseline."
- **Bugcrowd:** em ORIGEM_ESCOPO use "colado abaixo" (Bugcrowd não tem a API de sync
  do H1) e no P7 mapeie severidade pela **VRT**, não CVSS livre. Cheque no Brief se
  exige header de atribuição (`Bugcrowd-<researcher>`).

## Lembretes de higiene
`.env`, `targets/`, `loot/`, `findings/` (exceto `_EXAMPLE`) são git-ignored.
Nunca commite escopo privado, token ou achado real. Veja um engajamento completo
de exemplo em `EXAMPLE.md`.
