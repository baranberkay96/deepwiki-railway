# DeepWiki Open AI Wiki for Your Repos — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **DeepWiki Open AI Wiki for Your Repos** (no version in the name: upstream has no releases or tags; the build is pinned to commit `d92819a`) |
| Description | Turn any GitHub, GitLab or Bitbucket repo into an AI wiki with Q&A. (67 chars) |
| Category | AI/ML |
| Tags | deepwiki, documentation, wiki, rag, code-understanding, llm, github, mermaid |
| Icon | `https://cdn.jsdelivr.net/npm/lucide-static@1.59.0/icons/book-open-text.svg` (HTTP 200, image/svg+xml, ISC-licensed generic icon; DeepWiki-Open has no logo file in its repo and no entry in dashboard-icons/selfh.st) |
| Repo | `baranberkay96/deepwiki-railway`, root directory `/services/deepwiki` |
| User input at deploy | **Required:** `OPENAI_API_KEY` (enter `none` to use Gemini instead, then set `GOOGLE_API_KEY`). Everything else has a default or is generated. |

**Listing wording check.** Checked in the source: DeepWiki-Open clones a GitHub, GitLab or Bitbucket repository (public, or private with a personal access token entered in the UI), embeds it, generates a multi-page wiki with Mermaid diagrams, and answers questions about the code (RAG chat, "Deep Research", codemap guided tours). The description matches; it makes no claims about accuracy.

## Base market template

| Code | Name | Stats (Railway public API, 2026-10-20) | Verdict |
|---|---|---|---|
| `deepwiki-open` | "DeepWiki-Open" | 0 projects, 0 active, created 2026-09-17, unverified | Only market template. Image-only: `ghcr.io/youssefsiam38/deepwiki-railway:1.0.0` (third-party build, mutable tag, its source repo has no license). Same overall shape as this template (one service, Caddy basic auth in front, volume `/root/.adalflow`, `/health`, port 8080), so the shape was kept. Its files, image and README were not used; this template builds from upstream's own image and source. |

`_market/` was empty because the fetch script skips templates with 0 projects; the config above was read from Railway's public GraphQL API for comparison only.

## Pinned versions

| Component | Source | Version | Date | Checked |
|---|---|---|---|---|
| DeepWiki-Open API runtime (Python 3.11.16 venv, `/app/api`, Node 20.20.2, git) | `ghcr.io/asyncfuncai/deepwiki-open:sha-d92819a@sha256:730b72494f407397c896c586af0a31af9671d509af420e6792d834ff094a9c8f` | image label `org.opencontainers.image.revision=d92819a9c9f3b99416e3580ff235fc9d3adf8b89`; tag `sha-d92819a` = `main` = `latest` (same digest); amd64 manifest `sha256:1f24e9ab…af4c`, 273 MB compressed | built 2026-09-03 | 2026-10-20 |
| DeepWiki-Open UI source | `github.com/AsyncFuncAI/deepwiki-open` @ `d92819a9c9f3b99416e3580ff235fc9d3adf8b89` (= latest commit on `main`, 2026-09-03) | Next.js app rebuilt at build time | 2026-09-03 | 2026-10-20 |
| Next.js | npm `next@15.5.27` (upstream lock: 15.5.22, declared `^15.5.22`) | security bump, see "Deviations" | 2026-09-30 | 2026-10-20 |
| GitPython | PyPI `gitpython==3.1.61` (hash-pinned; upstream lock: 3.1.58, declared `^3.1.58`) | security bump | 2026-08-28 | 2026-10-20 |
| UI build stage | `node:20.20.2-trixie-slim@sha256:abfbe12c…1f35b` (build only; same Node release and Debian as the runtime) | — | — | 2026-10-20 |
| Edge | `caddy:2.11.7-alpine@sha256:d8542f48…5f75f` (binary copied into the runtime) | Caddy v2.11.7, released 2026-10-03 | — | 2026-10-20 |

The `_upstream/AsyncFuncAI__deepwiki-open` copy equals commit `d92819a` (all 178 git blob hashes compared).

**Upgrade path:** set `DEEPWIKI_SOURCE_COMMIT` and the base image digest in `services/deepwiki/Dockerfile` to a new upstream commit and its `sha-<short>` image (check the image's revision label). Rebuild: `patch_openai_stream.py` and `patch_ui.mjs` stop the build if the lines they patch changed (drop them once upstream fixes #585 and the slides/workshop WebSocket URL). Re-check the Next.js/GitPython pins against the new lockfiles.

## Architecture

```
Internet --HTTPS--> DeepWiki service (one container, public domain -> :8080)
  Caddy :8080 (dual-stack)
   |- /health                 -> API /health (no login; Railway healthcheck)
   |- /local_repo/*, /_next/image*  -> 404 (switched off)
   |- /api/*, /ws/*, /export/* started by another site (Sec-Fetch-Site) -> 403
   |- /ws/* with the session cookie -> API (WebSocket)
   '- everything else -> HTTP basic auth (BASIC_AUTH_USERNAME / BASIC_AUTH_PASSWORD)
        |- /ws/chat, /ws/codemap   -> API 127.0.0.1:8001 (WebSocket)
        '- /*                      -> Next.js 127.0.0.1:3000
                                       '- its /api/* routes and rewrites -> API 127.0.0.1:8001
  DeepWiki API (uvicorn, FastAPI) 127.0.0.1:8001
   |- clones repos (git), splits and embeds them, FAISS retrieval, wiki tasks, chat, codemap
   '- volume /root/.adalflow: repo/ (clones), repo/databases/ (embeddings), wikicache/, logs/
  Outbound: LLM/embedding provider APIs, github.com / gitlab.com / bitbucket.org
```

### Deviations from upstream `Dockerfile` / `docker-compose.yml` (at `d92819a`) and why

- **One public port.** Upstream exposes the UI (3000) and the API (8001) and the browser opens WebSockets to `<host>:8001`. Railway routes one domain to one port, so Caddy listens on `$PORT` and forwards `/ws/*` to the API and the rest to Next.js; both upstream processes listen on 127.0.0.1 only.
- **UI rebuilt from the same commit** with `NEXT_PUBLIC_API_PORT=443` (an upstream build option: the chat/codemap WebSocket then targets the page's own HTTPS port) and `SERVER_BASE_URL=http://127.0.0.1:8001` (baked into the Next.js rewrites at build). Built on Debian/glibc instead of upstream's Alpine builder, so the traced `sharp` binary matches the Debian runtime.
- **`patch_ui.mjs`** (3 lines): the slides and workshop pages build their WebSocket URL from `process.env.SERVER_BASE_URL || 'http://localhost:8001'`, which in the browser is the visitor's own localhost. They now use `window.location.origin`.
- **`patch_openai_stream.py`**: upstream's OpenAI streamer reads Chat Completions chunks, but adalflow 1.1.3 streams Responses API events, so every OpenAI generation fails (upstream issue #585, fix PR #586 open, not merged). The loop now reads `response.output_text.delta` events, still accepts chat chunks, and raises on `error`/`response.failed`. `check_openai_stream.py` feeds fake events through the patched code at build time.
- **Security bumps within upstream's declared ranges:** Next.js 15.5.22 → 15.5.27 (critical GHSA-2xp9-vwfh-vxw4 image-optimizer RCE and GHSA-p293-qw3h-jr36, medium cache-poisoning GHSA-4jqv-mc3x-m676 / GHSA-mcj8-r9mp-w47p); GitPython 3.1.58 → 3.1.61 (high GHSA-239g-whfq-7xj9: a cloned repository can make GitPython use attacker-controlled hooks; DeepWiki clones arbitrary repositories). `/_next/image` is also blocked at the edge (the app does not use it).
- **Login.** DeepWiki has no accounts. Its `DEEPWIKI_AUTH_MODE` only makes the UI ask for a code; the API checks the code only when deleting a wiki cache (`api/routers/wiki.py`), not for wiki generation, chat, codemap or repo indexing. So Caddy requires HTTP basic auth (generated password) for everything except `/health`, refuses credit-spending requests started by other sites, and strips the `Authorization` header before the app. WebSocket handshakes may use an HttpOnly, `SameSite=Strict`, `Path=/ws` cookie derived from the password instead, because some browsers do not send cached basic-auth credentials on WebSocket upgrades.
- **Provider defaults.** Upstream's UI preselects Google `gemini-2.5-flash` and embeds with OpenAI. `configure.py` writes a copy of upstream's config to `DEEPWIKI_CONFIG_DIR` (an upstream feature) with the default provider set to the configured key and a current default model: OpenAI `gpt-6-luna` (upstream's `gpt-5-nano` shuts down 2026-12-11 per OpenAI's deprecations page) or Google `gemini-3.8-flash` (Google limits the 2.5 models to accounts that already used them). `start.sh` picks the embedder that matches the key (`DEEPWIKI_EMBEDDER_TYPE`, upstream variable). Upstream config files are not modified.
- **Uvicorn started directly** (`python -m uvicorn api.main:app --host 127.0.0.1 --port 8001`) instead of `python -m api.main`, which hard-codes `0.0.0.0`. Same app object; no reload in production in either case.
- **Logs** go to stdout (Railway) and to `/root/.adalflow/logs/application.log` (upstream's rotating file handler, 10 MB × 5) on the volume instead of `/app/api/logs`.
- **Stored tokens scrubbed.** Upstream clones private repos with the token in the remote URL, which git keeps in `.git/config` on the volume. `start.sh` removes the credentials from those URLs at every start (the clones are never fetched again).
- **Thread pools** (`OMP/OPENBLAS/MKL/NUMEXPR_NUM_THREADS`) sized from the cgroup CPU quota, max 8, override `DEEPWIKI_CPU_THREADS` (Rule 8.15).
- **Concurrent wiki tasks** (`DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS`, upstream variable) default to half the CPU quota (min 1) instead of upstream's `os.cpu_count() // 2`, which is 48 on a 96-core Railway host and lets parallel submissions clone and index dozens of repositories in memory at once.
- **Not used from upstream:** the LiteLLM compose profile (Postgres + LiteLLM proxy pointing at an Ollama on the host machine). Its `LiteLLMClient` passes `chat_completion_parser`/`env_base_url_name` to adalflow 1.1.3's `OpenAIClient`, which does not accept them, so that provider looks broken at this commit; it is not offered here. `OPENAI_BASE_URL` is not offered either: upstream's generation path ignores it (adalflow's client has a fixed default base URL; only a `.bak` embedder config uses it).

## Services

### DeepWiki

- **Source:** GitHub repo `baranberkay96/deepwiki-railway`, root directory `/services/deepwiki` (Dockerfile: Node stage rebuilds the UI from the pinned commit; runtime = upstream image by digest + Caddy + patches)
- **Start command:** image default (`/app/railway/start.sh`: checks config, writes provider config, starts API, Next.js and Caddy; exits if any of them exits)
- **Healthcheck:** `/health` (API readiness through Caddy), timeout 300 s
- **Public domain:** yes → target port `8080`
- **TCP proxy:** none
- **Volume:** `/root/.adalflow`
- **Restart policy:** ON_FAILURE, max 5 retries (a configuration error stops after 5 attempts instead of looping)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Public port (Caddy). Railway health-checks /health here; UI and API stay on localhost. |
| `BASIC_AUTH_USERNAME` | `admin` | Login name for the DeepWiki UI and API (letters, digits, . _ @ -). |
| `BASIC_AUTH_PASSWORD` | `${{secret(32, "a–zA–Z0–9")}}` | Login password (generated; read it here). Everything except /health requires it. |
| `OPENAI_API_KEY` | *(required)* | Required. OpenAI key for wiki/chat generation and embeddings. Gemini only? Enter none. |
| `GOOGLE_API_KEY` | *(empty)* | Optional. Gemini API key; used for generation and embeddings when OPENAI_API_KEY is none. |
| `OPENROUTER_API_KEY` | *(empty)* | Optional. Adds OpenRouter models to the UI (embeddings still need OpenAI or Gemini). |
| `OLLAMA_HOST` | *(empty)* | Optional. URL of your own Ollama server (e.g. http://ollama.railway.internal:11434). |
| `DEEPWIKI_PROVIDER` | `auto` | Provider preselected in the UI: auto (first key set), openai, google, openrouter, ollama. |
| `DEEPWIKI_MODEL` | *(empty)* | Optional default model id for that provider. Empty: gpt-6-luna / gemini-3.8-flash. |
| `DEEPWIKI_EMBEDDER_TYPE` | *(empty)* | Embeddings: empty = auto (openai, google or ollama). Changing it needs a re-index. |
| `DEEPWIKI_AUTH_MODE` | `false` | true = UI also asks DEEPWIKI_AUTH_CODE before generating/deleting. Not a login. |
| `DEEPWIKI_AUTH_CODE` | `${{secret(16, "a–zA–Z0–9")}}` | Code for DEEPWIKI_AUTH_MODE (generated). Only used when that mode is true. |
| `DEEPWIKI_CPU_THREADS` | *(empty)* | Optional. FAISS/numpy threads; empty = from the service CPU limit, max 8. |
| `DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS` | *(empty)* | Optional. Wikis generated at the same time; empty = half the CPU limit (min 1). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Shutdown grace so open chats and streams close cleanly on redeploy. |

`DEEPWIKI_PROVIDER` also accepts `bedrock`, `azure` and `dashscope`; their credentials (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION`, `AZURE_OPENAI_API_KEY`/`AZURE_OPENAI_ENDPOINT`/`AZURE_OPENAI_VERSION`, `DASHSCOPE_API_KEY`) can be added as variables; they are upstream's names and were not added to the form to keep it short.

### Provider choices (documented for users)

| Setup | Variables | Generation | Embeddings |
|---|---|---|---|
| **OpenAI (default)** | `OPENAI_API_KEY` | OpenAI, default `gpt-6-luna` (Responses API, patched streamer) | `text-embedding-3-small`, 256 dims (upstream default) |
| **Gemini only** | `OPENAI_API_KEY=none`, `GOOGLE_API_KEY` | Gemini, default `gemini-3.8-flash` | `gemini-embedding-001` |
| **OpenRouter + embeddings key** | `OPENROUTER_API_KEY`, `DEEPWIKI_PROVIDER=openrouter`, plus `OPENAI_API_KEY` or `GOOGLE_API_KEY` | any OpenRouter model (upstream default `openai/gpt-5-nano`) | OpenAI or Gemini (DeepWiki cannot embed via OpenRouter, upstream issue #490) |
| **Own Ollama** | `OLLAMA_HOST`, `DEEPWIKI_PROVIDER=ollama`, `OPENAI_API_KEY=none` | Ollama models (`qwen3:1.7b` …) | `nomic-embed-text` on the same Ollama |

All keys may be set at once; the UI lists every provider and the user can switch per wiki. The embedder is one per deployment: indexes built with one embedder must be rebuilt after switching (delete the wiki in the UI and generate it again).

## Improvements over market templates

| # | Market template (`deepwiki-open`) | This template |
|---|---|---|
| 1 | Third-party image `ghcr.io/youssefsiam38/deepwiki-railway:1.0.0` (mutable tag; build repo has no license) | Upstream's own image pinned by digest (= commit `d92819a`), UI rebuilt from the same commit in the open, every base image pinned by digest |
| 2 | OpenAI generation path as upstream: fails on every wiki/chat with adalflow 1.1.3 (issue #585) | Patched and checked at build with fake Responses API events |
| 3 | No LLM key required: deploy succeeds, then every wiki fails | `OPENAI_API_KEY` required in the form (`none` + `GOOGLE_API_KEY` for Gemini); start-up stops with a clear message if no usable provider or embedder is configured (e.g. OpenRouter without an embeddings key) |
| 4 | UI preselects Google `gemini-2.5-flash` and OpenAI `gpt-5-nano` | Default provider follows the configured key; defaults `gpt-6-luna` / `gemini-3.8-flash` (upstream defaults are retiring / closed to new Gemini users); `DEEPWIKI_MODEL` override |
| 5 | Advertises `OPENAI_BASE_URL` for OpenAI-compatible endpoints | Not offered: upstream generation ignores it. OpenRouter and Ollama are offered through their own clients |
| 6 | Basic auth only | Basic auth + cross-site request refusal on credit-spending endpoints + `/local_repo` directory listing and `/_next/image` closed + WebSocket session cookie for browsers that drop credentials on upgrades |
| 7 | Upstream dependency versions (as far as visible) | Next.js 15.5.27 and GitPython 3.1.61 (critical/high advisories fixed), hash-pinned |
| 8 | Private-repo tokens stay in cloned `.git/config` on the volume | Removed at every start |
| 9 | `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` as a required form field | Healthcheck path and timeout set in the service config; nothing to fill in |
| 10 | Thread pools and parallel wiki tasks sized to the host's cores (`cpu_count() // 2` tasks) | Sized to the CPU quota: threads max 8, tasks = half the quota (Rule 8.15) |
| 11 | README generic closing text | README with provider setup, cost control, first login and upgrade steps |

## Scaling

- **1 replica.** Wiki tasks run in the API process (in-memory task registry) and the data lives on the volume, which replicas cannot share. Scale vertically: indexing a large repository holds its chunks and embeddings in memory (upstream's compose reserves 2 GB and caps at 6 GB).
- Generation throughput is bounded by the LLM provider's rate limits more than by Railway resources. Upstream generates one page at a time per wiki (`DEEPWIKI_WIKI_PAGE_CONCURRENCY`, default 1, can be added as a variable) and runs `DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS` wikis in parallel; free tiers and new provider accounts hit rate limits first.
- A redeploy stops running wiki tasks (they are not resumable upstream); finished wikis and indexes stay on the volume.

## Resource estimate

Prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Builds are not billed. Figures are **estimates from the process mix and upstream's compose limits, not measurements** (nothing was run). LLM and embedding usage are billed by the provider.

| Process | Idle RAM | Typical RAM | vCPU idle / busy |
|---|---|---|---|
| Caddy | 15–25 MB | 30 MB | 0.00 / 0.02 |
| Next.js server | 80–150 MB | 150–250 MB | 0.00 / 0.1 |
| DeepWiki API (FastAPI, adalflow, FAISS, provider SDKs) | 250–400 MB | 0.5–1.5 GB while indexing/generating; 2–4 GB for very large repos | 0.01 / 0.5–1 |
| **Total** | **≈ 0.4–0.6 GB** | **≈ 0.7–1.8 GB** | **≈ 0.02 / up to 1** |
| Volume | — | clones (depth 1) + embeddings + wiki JSON: ≈ 20–300 MB per repo | — |

- **Idle:** 0.5 GB × $10 + 0.02 vCPU × $20 + 1 GB × $0.15 ≈ **$5.5/month**.
- **Typical (small team, a few wikis a week, daily Q&A):** ≈ 0.8 GB average, 0.05–0.1 vCPU, 2–5 GB volume → **≈ $9–12/month**.
- **Heavy (large monorepos re-indexed often, many users):** ≈ 2 GB average, 0.3 vCPU → **≈ $27–30/month**.
- **Provider cost (estimate, list prices on 2026-10-20):** embeddings with `text-embedding-3-small` cost $0.02 per 1M tokens (a 2M-token repo ≈ $0.04); a wiki with `gpt-6-luna` ($0.10 / $0.50 per 1M input/output tokens) is typically cents, more with larger models or Deep Research.
- **Minimum plan: Hobby.** The image fits Trial limits (≈ 0.3 GB compressed), but indexing a medium repository can exceed Trial's 1 GB RAM. Hobby's 5 GB volume holds dozens of typical repositories; Pro for large monorepos or many users.

## Verification checklist

Nothing has run yet (no Docker this round). On the first Railway deploy:

1. **Build log:** `patch_ui.mjs` reports 2 + 1 patched lines; `npm install … next@15.5.27` and the version test pass; `next build` succeeds and the `routes-manifest.json` grep passes; pip installs `gitpython-3.1.61` with hash check; "patched OpenAI Responses API stream handling" and "OpenAI stream patch: Responses events, chat chunks and failures handled"; `import api.main` succeeds; `caddy validate` prints "Valid configuration"; both `configure.py` checks print a config line.
2. **Start log:** `[deepwiki] config /tmp/deepwiki-config: default provider=openai model=gpt-6-luna` and `[deepwiki] provider=openai embedder=openai threads=N wiki_tasks=M login user="admin" …` (N = the service's vCPU limit up to 8); no "not a mounted volume" warning; uvicorn "Application startup complete"; Next.js "Ready".
3. **Health:** service Active; `curl -i https://{domain}/health` → 200 JSON `"status":"healthy"` without credentials.
4. **Auth:** `curl -i https://{domain}/` → 401; with `-u admin:{BASIC_AUTH_PASSWORD}` → 200 and a `Set-Cookie: deepwiki_ws=…` header when `Accept: text/html` is sent. `curl -u admin:{pw} -H 'Sec-Fetch-Site: cross-site' https://{domain}/api/wiki/projects` → 403. `curl -i https://{domain}/local_repo/structure?path=/` → 404. `curl -i https://{domain}/_next/image?url=/next.svg&w=64&q=75` → 404.
5. **UI:** sign in from the browser prompt; the model picker preselects OpenAI / `gpt-6-luna`.
6. **Wiki (needs a real key):** generate a wiki for a small public repo (e.g. `https://github.com/AsyncFuncAI/deepwiki-open`) → progress stream, pages with Mermaid diagrams. If generation fails with a parameter error for `gpt-6-luna`, set `DEEPWIKI_MODEL=gpt-5-mini` and report it.
7. **WebSockets:** in the wiki view, Ask a question → answer streams; browser devtools show `wss://{domain}/ws/chat` with status 101 (not a fallback POST to `/api/chat/stream`). Run a codemap question → `wss://{domain}/ws/codemap` 101 and a codemap with citations. Repeat in Safari and Firefox if possible (cookie path).
8. **Slides/workshop:** open the slides page of the generated wiki → it connects to `wss://{domain}/ws/chat` (no localhost connection or local-network permission prompt).
9. **Gemini path:** redeploy with `OPENAI_API_KEY=none` and `GOOGLE_API_KEY` → start log `provider=google embedder=google`, model `gemini-3.8-flash`; generate a wiki for another repo.
10. **Private repo:** generate with a fine-grained read-only token; after a redeploy, the start log says "removed stored access tokens from 1 cloned repositories" and the wiki is still listed.
11. **Persistence:** redeploy → the processed-projects list and cached wikis are still there; asking a question on an indexed repo does not re-embed it.

## Open questions

- **Nothing has run.** No image was built or started; the Railway deploy test is the first real run.
- **`gpt-6-luna` and `gemini-3.8-flash`** were chosen from the providers' current model and deprecation pages; they were not called. GPT-6 models are reasoning models; upstream sends `temperature: 1.0` (inherited from the `gpt-5` entries, which accept only the default). If either model rejects a parameter, `DEEPWIKI_MODEL` switches the default without a rebuild.
- **Gemini 3.x through `google-generativeai` 0.8.6** (upstream's legacy SDK) was not exercised; plain `generateContent` streaming is expected to work.
- **Next.js 15.5.27 with `npm install --no-save`** after `npm ci`: expected to change only `next`, `@next/env` and the `@next/swc-*` binaries. If it fails, removing that line rebuilds upstream's 15.5.22 (the critical advisory's endpoint stays blocked by Caddy and the server is loopback-only).
- **Basic auth on WebSockets:** Chrome and Firefox normally send cached credentials on the upgrade; the cookie path covers browsers that do not. Both paths unverified.
- **`Sec-Fetch-Site` guard** relies on modern browsers (all current ones send it); older browsers fall back to basic auth only.
- **Upstream's own bugs not fixed here:** the LiteLLM provider (constructor mismatch with adalflow 1.1.3), Azure via the same streamer (now uses the patched loop, untested), and UI model entries that OpenAI retires (`o1`, `o4-mini` on 2026-10-23; `gpt-5`, `gpt-5-mini`, `gpt-5-nano`, `o3` on 2026-12-11, per OpenAI's deprecations page); users can type any model id in the UI.
- **Repo name** `baranberkay96/deepwiki-railway` as given in the task.

## Local verification (2026-10-20)

Docker was not used (instruction for this round). Checks that ran:

| Check | Result |
|---|---|
| `bash -n services/deepwiki/start.sh`; `python3 -m py_compile` on all Python files | **Pass** |
| `start.sh` under bash 3.2 with stubbed `caddy`/`python`/`node`: OpenAI-only, Gemini via `none`, OpenRouter without embeddings key (stops), OpenRouter + Gemini, no key (stops), forced provider without key, bad provider/embedder, key with whitespace, model override, bad username, short and multi-line password, auth mode without code, token scrub of a cloned `.git/config`; password reaches `hash-password` on stdin only and is unset before Caddy starts | **Pass** (process supervision uses `wait -n`, bash ≥ 5.1 in the image; not run locally) |
| Thread and wiki-task sizing from fake `cpu.max` (8, 3, 2, 1.5, 1, 32, unlimited, 0.5 CPU, missing file, overrides, invalid values) | **Pass** |
| `configure.py` on upstream's config: openai/google/openrouter/ollama/azure/bedrock, `DEEPWIKI_MODEL` override, invalid provider/model, missing dir; embedder/repo/lang files byte-identical | **Pass** |
| `patch_openai_stream.py` + `check_openai_stream.py` on upstream `_stream.py` with stub `adalflow`/`api.config`: check fails before the patch (`AttributeError: … 'choices'`, = issue #585), passes after; idempotent; refuses changed upstream code | **Pass** |
| `patch_ui.mjs` (node 24) on upstream slides/workshop pages: 2 + 1 lines patched, idempotent, refuses changed code | **Pass** |
| `template.json` parses, every variable described, description 67 chars, `_tools/to_serialized.py` converts it (1 service, volume, domain on 8080) | **Pass** |
| Image references exist (registry API, no pull): upstream `sha-d92819a` = `main` = `latest` (`sha256:730b7249…`, revision label `d92819a…`), `node:20.20.2-trixie-slim`, `caddy:2.11.7-alpine`; runtime Node 20.20.2 read from the image's `node_version.h`; venv contents (pip, adalflow 1.1.3, gitpython 3.1.58, uvicorn 0.52.1, websockets 17.0.1) listed from the layer | **Pass** |
| `_upstream` copy vs commit `d92819a` (178 blob hashes) | **Pass** |
| Caddyfile constructs against Caddy v2.11.7 source (`basic_auth [alg [realm]]` with hash cache, `hash-password` reads stdin, header matcher `*x*` substring/placeholders, repeated header lines OR'ed) | **Pass** (source reading; `caddy validate` runs in the build) |
| Advisory lookups (GitHub Advisory DB): next 15.5.22 affected, 15.5.27 none; gitpython 3.1.58 affected, 3.1.61 none | **Pass** |
| `docker build --platform linux/amd64`; running the stack | **Not run (unverified)** |
