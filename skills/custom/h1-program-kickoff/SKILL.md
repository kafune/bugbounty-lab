---
name: h1-program-kickoff
description: "Day-0 runbook for starting a NEW HackerOne program from its scope. Use the moment you are handed a program's scope (CSV export, pasted asset table, or policy page) and need to go from nothing to a working recon workspace, mapped attack surface, and the first concrete leads. Covers: scope parsing (wildcards, max-severity, eligibility, out-of-scope), correct attribution headers per policy, the fingerprint->JS-mining->sourcemap->API-auth pipeline, finding PROVIDED test credentials (Postman collections / TestFlight / sample tokens), cloud-misconfig quick wins, and routing into the right hunt-* skills. Complements bb-methodology (mindset/phases) with concrete copy-paste commands. Trigger phrases: 'start this program', 'new bug bounty target', 'here is the scope', 'begin recon on <program>'."
sources: field_recon, hackerone_public
report_count: 1
version: 1.0.0
---

# HackerOne Program Kickoff — Day-0 Runbook

Goal: from "here is a program's scope" → a working workspace, a mapped surface, and the
first real leads, in one focused session. This is the concrete onboarding pipeline. For
*what to do next / which vuln class*, hand off to `bb-methodology`; for killing/keeping a
finding, hand off to `triage-validation`; for write-ups, `report-writing`.

> **Runnable helpers:** the command blocks below are packaged as scripts in `scripts/`
> (`fingerprint.sh`, `js-mine.sh`, `sourcemap.py`, `firebase-storage.sh`, `postman-auth.py`;
> shared `_lib.sh`). All take `H1USER` for attribution; run shell scripts with `bash`. See
> `scripts/README.md`. The inline snippets here are the same logic, kept for quick reference.

> One-line kickoff prompt you can paste to start a program:
> *"Start a new HackerOne bug bounty engagement. Scope is in `<scope.csv|pasted below>`,
> attribution handle `<h1-username>`. Run the h1-program-kickoff skill: set up the workspace,
> parse in/out-of-scope, find any provided test credentials, fingerprint every in-scope host,
> mine JS/sourcemaps, map the API + auth model, and give me ranked leads with honest severity."*

---

## PHASE 0 — Rules of engagement (do this FIRST, never skip)

1. **Attribution header.** Read the policy's "Session Layer / HTTP Headers" section. Programs
   demand a specific identifier on *every* request. Common forms:
   - `X-HackerOne-Research: <username>`  ·  `User-Agent: <username>`  ·  `X-Bug-Bounty: <handle>`
   Set it as a shell var and put it on every curl. Losing attribution = test traffic looks like
   an attack. Keep it even when you swap to a browser UA (below).
2. **Scope boundaries.** Note `Eligible` vs `Ineligible`, `Max severity`, and OUT-of-scope assets.
   *"Ask the program before testing unscoped subdomains"* is common — respect it. A host the app
   references (e.g. a sign/evidence backend) is often NOT in scope even if reachable.
3. **Out-of-scope vuln classes.** Skim the exclusions list NOW (CSP best-practice, missing
   cookie flags, clickjacking on no-action pages, outdated-browser-only, DoS, rate-limiting on
   unauth endpoints, open-redirect-without-impact…). Don't waste a session on these.
4. **Provided test material** — see Phase 2. This is the single biggest force-multiplier.

```bash
export H1USER="<your-h1-username>"            # attribution
export UA="$H1USER"                            # some programs want UA = username
export BUA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# every request: -A "$BUA" -H "X-HackerOne-Research: $H1USER"   (browser UA bypasses Cloudflare bot-mgmt; header keeps attribution)
```

---

## PHASE 1 — Workspace + scope parsing

```bash
mkdir -p recon && cd recon
# FINDINGS.md = single source of truth; one numbered section per lead, honest status tags.
printf '# %s — findings\n\n## Scope\n' "$PROGRAM" > FINDINGS.md
```

Parse the scope (CSV export or pasted asset table) into three buckets — **in-scope (with
wildcards + max severity + eligibility)**, **out-of-scope**, **provided test assets**. If it's a
CSV: `python3 -c "import csv,sys;[print(r) for r in csv.reader(open('scope.csv'))]"`. If pasted,
extract every host/wildcard. Expand wildcards mentally (`*.uat.example.app`, `*.cadastro…`).

Write the scope summary to the top of `FINDINGS.md` and save a **memory** entry (program name,
H1 handle, in/out scope, recon layout) so it survives context resets.

---

## PHASE 2 — Hunt for PROVIDED credentials & test material  ⭐ highest ROI

Before any blind probing, mine the **policy + attachments** for things that unlock authenticated
surface. These routinely turn a "hardened, needs-JWT" wall into a full client:

- **Postman / Insomnia collections** (`*.postman_collection*.json`, attachment IDs like `F1234567`).
  These often ship a **service account + private key + tenant id + sample token + every endpoint**.
  Parse it: collection `variable`s (keys, tenant, secret_key), folder `item`s (URLs/methods/bodies),
  and `event` pre-request scripts (they show the **exact JWT/HMAC auth construction**). Reproduce the
  token-minting in Python (`PyJWT` for RS256/HS256 JWT-bearer → `/oauth2/token`).
- **TestFlight / APK / IPA links**, sample logins, "fictitious test data" notes, Postman environments.
- **DevCenter / API-reference URLs** — the documented endpoint map saves hours.

> Decode any provided token (`jwt.decode(t, options={"verify_signature":False})`) — the claims leak
> tenant id, client id, scopes, and whether it's already expired (mint a fresh one if so).

If the program ships credentials, the engagement's center of gravity is the **authenticated API**
(IDOR/BOLA/tenant-isolation), not unauth recon.

> `bash`→`python3 scripts/postman-auth.py <collection.json> [--mint]` — dumps vars/endpoints,
> decodes baked tokens, and mints a fresh JWT-bearer token (`token.txt`).

---

## PHASE 3 — Fingerprint every in-scope host

One sweep, browser UA + attribution header, capture code/type/size/title/server/cf-ray. Write a
bash script and run with `bash` (see Gotchas — zsh breaks inline curl loops).

> `scripts/fingerprint.sh <hosts.txt | host...>` — does this sweep and auto-classifies the
> backend signatures below.

```bash
# for each host: https code, content-type, size, redirect Location, Server/cf-ray, <title>
curl -s -k -m12 -A "$BUA" -H "X-HackerOne-Research: $H1USER" -D - -o /tmp/b "https://$h/" \
  | grep -iE '^(location|server|cf-ray|content-type|x-powered):'
```

Classify each host: SPA (Angular/React/Vue/Flutter) · API gateway · redirect/login · challenge.
Tell-tale backend signatures:
- `Unable to route the message to a Target Endpoint` / `RouteFailed` → **Apigee**, no proxy mounted.
- `RBAC: access denied` → **Istio** mesh, needs a valid JWT.
- `415 application/grpc` on every path → **gRPC-Web** backend (needs gRPC framing, not JSON).
- `<Error><Code>NoSuchBucket/AccessDenied…</Code>` + `via: 1.1 google` → **GCS** static hosting.
- `403 "Just a moment…/Attention Required"` → **Cloudflare** bot challenge → retry with `$BUA`.

---

## PHASE 4 — Mine JavaScript + sourcemaps (the surface is in the bundles)

SPAs hide the whole API contract in their JS. For each SPA:

> `scripts/js-mine.sh <base-url>` (pull bundles + check `.map` + grep surface) then
> `scripts/sourcemap.py <map-url> <outdir>` (reconstruct on a 200).


1. Pull `index.html`, list `<script>`/asset refs, fetch each bundle.
2. **Check for `.map`** on every bundle (`curl -o /dev/null -w '%{http_code}' "$B/main.js.map"`).
   A `200` = **source-code disclosure** *and* a gift: reconstruct it.
   - Parse `sources` + `sourcesContent`; strip the webpack prefix. It is NOT always `webpack:///` —
     module-federation apps use `webpack://<project>/` (e.g. `webpack://you-payment/./src/...`).
     Normalize `../` and keep app `src/` + `libs/`, drop `node_modules`.
3. Grep bundles (or reconstructed source) for: API hosts (`https://…/(api|client)/v…`), endpoint
   path constants, `clientID`/UUIDs, env vars (`NX_PUBLIC_*`, `VITE_*`, `REACT_APP_*`), auth flow
   (`/login/start`, `/oauth2/token`, PKCE `codeVerifier`, `Authorization`/`Session-Data` headers),
   secrets (`AIza…`, `firebaseio`, `appspot.com`, JWTs, `BEGIN PRIVATE KEY`).
4. Runtime config: if env vars are NOT inlined, look for `/assets/config.json`, `/env.js`,
   `window.__ENV__`, `.version.js`.

Tiny `index.js` (Vite) = loader shell → follow its lazy chunk names (`buildApp-*.js`) for the real
code. Flutter apps: mine `main.dart.js` string literals + `/assets/AssetManifest.json` + Firebase
project ids. → Route deep work to `source-leak-hunt` / `js-secrets-extraction`.

---

## PHASE 5 — Map the API + auth model, then test authz

With endpoints + (provided) credentials in hand:

1. **Reproduce auth.** Mint the token exactly as the bundle/collection does. Confirm a baseline
   authenticated call works (200). Decode the token's claims (tenant/aud, scopes, sub).
2. **Tenant / object isolation (BOLA/IDOR)** — the money class for multi-tenant APIs:
   - Client sends an **array of IDs it wants** (companies/orgs/accounts)? Try IDs you don't own.
   - **List endpoints**: does the result scope to your tenant, or leak across tenants?
   - **Tenant override**: replay your token with `X-Tenant`/`Acesso-Account-Id`/`X-Org-Id`/… set to
     another tenant/`*`. Result-set changes = broken authz.
   - **Token minting across tenants**: change the `iss`/tenant in the signed assertion — does the
     IdP bind it to the key, or issue a cross-tenant token?
   - Raw `GET /resource/{id}` with another user's id; **magic-link** flows (`/process/{uuid}`) where
     the id is the *only* credential.
   - → `hunt-idor`, `hunt-grpc`, `jwt-attack`, `api-noauth-hunt`.
3. **Note masking vs full PII** (list masks, single-GET/create echoes full?) and shared-test-tenant
   caveats (fictitious data ≠ impact).

---

## PHASE 6 — Cloud & misconfig quick wins (parallel to API work)

- **Firebase Storage** (bucket from `*.appspot.com` in JS): GCS XML API may deny anon list, but the
  Firebase REST API often doesn't: `GET https://firebasestorage.googleapis.com/v0/b/<bucket>/o`.
  Then test object **read** (`/o/<urlenc>?alt=media`) and **write** (upload a uniquely-named harmless
  marker — *outward mutation: confirm with the user first*). → `hunt-firebase`, `firebase-supabase-attack`.
  > `scripts/firebase-storage.sh <bucket> list|read <obj>|write-poc` (write-poc is authorization-gated).
- **GCS / S3 buckets**, RTDB (`<proj>.firebaseio.com/.json`), `.git`, `.env`, source maps, swagger.
  → `hunt-cloud-misconfig`, `source-leak-hunt`.
- **OAuth/OIDC**: pull `.well-known/openid-configuration`; test `redirect_uri` validation
  (substring/suffix bypass `https://legit.tld.attacker.com`), PKCE leakage. → `hunt-oauth`, `hunt-saml`.

---

## PHASE 7 — Validate honestly & record

- Every lead → a numbered `FINDINGS.md` section with an explicit status tag: `CONFIRMED` ·
  `NEGATIVE/secure` · `BLOCKED (needs account)` · `LOW/INFO` · `DUP-RISK`. Negatives are valuable —
  record what you tested so you don't re-walk it.
- Before drafting any report, run **`triage-validation`** (7-Question Gate). Kill what fails.
- **Dup awareness**: shared-test-tenant artifacts (e.g. another researcher's marker file, a planted
  `security-test.txt`) and "resolved reports > 0" on an asset signal the easy bugs are taken. Date
  correlation (a planted file dated the same day as a known report) hints a finding may be known.
- Severity honestly: dev/UAT + fictitious data lowers impact; separate *proven* from *inferred*.
- Update **memory** with the program map and every confirmed/negative so the next session resumes.

---

## Worked example — Unico IDtech (the run this skill was distilled from)

- **P0/P1** — Scope CSV → in-scope wildcards `*.uat.unico.app`, `*.cadastro.uat.unico.app`,
  `unico.io`+subs, `identityhomolog.acesso.io`. Attribution `X-HackerOne-Research`. `recon/FINDINGS.md`.
- **P2** — Policy shipped a Postman collection (`F6075879`): service account `cbounty`, an RSA
  `secret_key`, tenant `securitylab`, and a pre-request script building an RS256 JWT-bearer assertion.
  Reproduced it in `PyJWT` → `POST identityhomolog.acesso.io/oauth2/token` → fresh access token. This
  unlocked the whole authenticated `api.cadastro.uat.unico.app/client/v1` surface (which was otherwise
  an Apigee+Istio wall).
- **P3** — Fingerprint flagged `backend-sdk…` as Apigee (`RouteFailed`), `api.idcash…` as gRPC-Web
  (`415 application/grpc`), `secure.unico.io` as a Flutter app, the SPAs on GCS (`via: 1.1 google`).
- **P4** — `idcash-uat.unico.io/main.js.map` → **200** (source disclosure). Reconstructed 113 React
  files (`webpack://you-payment/...` prefix). Source exposed the API contract incl. a BOLA-shaped
  `transactions/list` that takes a client-controlled `companies[]` array, and a Firebase bucket id.
- **P5** — With the minted token: tenant isolation held — cross-tenant token mint → 401, tenant-override
  headers → 400, list endpoint tenant-scoped + PII masked. Clean **NEGATIVE** (recorded, not re-walked).
- **P6** — Firebase `acesso-unico-dev.appspot.com`: Firebase REST `/v0/b/<bucket>/o` listed 294 objects
  unauth (GCS XML API denied it) → read confirmed; **write tested with user OK → denied (403)**, so
  downgraded honestly to Low/Info read-only.
- **P7** — OAuth `redirect_uri` substring bypass came back a **DUP** of an earlier report; the Firebase
  marker file `simple.txt` was dated the same day as that report (dup-risk signal). Net: honest mix of
  one dup, two well-built negatives, one Low — no inflation.

Lesson ranking from this run: **P2 (provided creds) > P4 (sourcemaps) > P5/P6 (authz + cloud).**

## Gotchas that cost real time (learned in the field)

- **zsh**: does NOT word-split unquoted `$vars`, and `curl` can fail inside `$( )`/`< <( )`
  subshells. Symptom: "command not found" / one arg treated as a filename. Fix: write a
  `script.sh` and run `bash script.sh`; use bash arrays for multi-file lists.
- **httpx colored output**: strip ANSI before grep → `sed -r 's/\x1b\[[0-9;]*m//g'`.
- **Cloudflare 403** on recon UA → switch to `$BUA`; keep the attribution header.
- **katana** hangs/0-urls on `URL [status]` lines → feed bare URLs (`awk '{print $1}'`) and cap
  (`-ct 120 -timeout 10 -c 15 -rl 50`).
- **SPA 404→200 catch-all**: path-probing returns the index page (200) for everything — don't treat
  that as "endpoint exists". Diff against a known-bogus path.
- **Firebase write test** and any **upload/POST to third-party storage** is an *outward mutation* —
  get explicit user authorization first; use a unique non-overwriting name; attempt cleanup.

## Routing table (hand off after kickoff)
| Surface found | Skill |
|---|---|
| Mindset / "what next" / phase | `bb-methodology`, `bug-bounty` |
| Exposed sourcemaps / JS secrets | `source-leak-hunt`, `js-secrets-extraction` |
| OAuth / OIDC / SAML | `hunt-oauth`, `hunt-saml`, `jwt-attack` |
| Multi-tenant API IDOR/BOLA | `hunt-idor`, `hunt-grpc`, `api-noauth-hunt` |
| Firebase / Supabase / cloud bucket | `hunt-firebase`, `firebase-supabase-attack`, `hunt-cloud-misconfig` |
| File upload / RCE / SSRF / XSS | `hunt-file-upload`, `hunt-rce`, `hunt-ssrf`, `hunt-xss` |
| Subdomain / surface expansion | `hunt-subdomain`, `subdomain-enumeration`, `web-enumeration` |
| Validate finding / write report | `triage-validation`, `report-writing` |
