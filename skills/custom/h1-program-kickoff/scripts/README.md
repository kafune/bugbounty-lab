# h1-program-kickoff — scripts

Runnable helpers for the kickoff phases. All require `H1USER` (your HackerOne handle) for
attribution. Run shell scripts with `bash` (not zsh — see the skill's Gotchas).

> **Repo integration** — dentro do bugbounty-lab, as fases mecânicas já são automatizadas:
> `make sync HANDLE=<prog>` materializa o escopo (Fase 1) e `make recon PROG=<prog>` gera
> `loot/<prog>/live-urls.txt`, que o `fingerprint.sh` consome na Fase 3.
> Variáveis: `H1USER` = **atribuição** (header em cada request, usado por estes scripts);
> `H1_USER`/`H1_TOKEN` = **API auth** do `bin/h1sync.py`. Coisas diferentes; ambas no `.env`.

| Script | Phase | What it does |
|---|---|---|
| `_lib.sh` | — | shared: attribution headers, `req()` helper, `strip_ansi`. Sourced by the others. |
| `postman-auth.py` | 2 | parse a provided Postman collection: dump vars/endpoints, decode baked tokens, `--mint` a fresh JWT-bearer token. |
| `fingerprint.sh` | 3 | fingerprint hosts (code/type/title/server) + classify Apigee / Istio / gRPC-Web / GCS / Cloudflare. |
| `js-mine.sh` | 4 | pull a SPA's bundles, check every `.map`, grep for API hosts / endpoints / env / secrets / UUIDs. |
| `sourcemap.py` | 4 | reconstruct source from a `.map` (handles `webpack://<proj>/` module-federation prefixes). |
| `firebase-storage.sh` | 6 | test a Firebase bucket: `list` / `read <obj>` / `write-poc` (write gated behind explicit authorization). |

## Quick start

```bash
export H1USER=yourname

# P2 — provided creds (biggest unlock)
python3 postman-auth.py ./Some_Collection.postman_collection.json --mint   # -> token.txt

# P3 — fingerprint
bash fingerprint.sh ../scope_hosts.txt

# P4 — JS + sourcemaps
bash js-mine.sh https://app.target.com           # prints which bundles expose .map
python3 sourcemap.py https://app.target.com/main.js.map  src_app

# P6 — Firebase
bash firebase-storage.sh target-proj.appspot.com list
bash firebase-storage.sh target-proj.appspot.com read "path/to/object.json"
# write test is an OUTWARD MUTATION — only after user sign-off:
I_HAVE_USER_AUTHORIZATION=yes bash firebase-storage.sh target-proj.appspot.com write-poc
```

> `postman-auth.py --mint` assumes the common `service_account@tenant.iam…` assertion shape.
> If the program's pre-request script differs, the script prints the payload it will send —
> adjust `iss`/`aud` to match before relying on it.
