# Notice

## Upstream software

| Software | License | How it is used here |
|---|---|---|
| DeepWiki-Open (Python API and Next.js UI) — Copyright (c) 2024 Sheing Ng, github.com/AsyncFuncAI/deepwiki-open | MIT | Runtime: upstream's published image `ghcr.io/asyncfuncai/deepwiki-open:sha-d92819a` (pinned by digest). UI: rebuilt at build time from upstream commit `d92819a9c9f3b99416e3580ff235fc9d3adf8b89`. Two small modifications are applied at build time (see below); upstream's configuration files are copied unchanged into a runtime config directory, with only `default_provider`/`default_model` set. |
| AdalFlow, FastAPI, Uvicorn, FAISS, OpenAI/Google/Anthropic/boto3 SDKs and other Python dependencies | Various OSI licenses (MIT, Apache-2.0, BSD) | Installed in the upstream image per `api/poetry.lock` |
| GitPython 3.1.61 | BSD-3-Clause | Installed over the image's 3.1.58 (security fix), hash-pinned from PyPI |
| Next.js 15.5.27, React and other npm dependencies | MIT and others | Installed at build time per upstream's `package-lock.json`, with `next` raised to 15.5.27 |
| Caddy | Apache-2.0 | Binary from `caddy:2.11.7-alpine` (Docker Official Image) |
| Node.js | MIT | `node:20.20.2-trixie-slim`, build stage only; the runtime uses the Node.js shipped in the upstream image |
| Lucide icon `book-open-text` | ISC | Marketplace and service icon, loaded from jsDelivr (`lucide-static@1.59.0`) |

LLM and embedding providers (OpenAI, Google, OpenRouter, others) and Git hosts are used under their own terms and bill the user directly.

### DeepWiki-Open license (MIT)

```
MIT License

Copyright (c) 2024 Sheing Ng

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Modifications to DeepWiki-Open (applied at build time, MIT permits this)

| File in DeepWiki-Open | Change | Script |
|---|---|---|
| `api/chat/_stream.py` (`_OpenAICompatStreamer.respond_stream`) | Reads OpenAI Responses API stream events (`response.output_text.delta`), keeps Chat Completions chunks, raises on `error`/`response.failed`. Fixes upstream issue #585 (same approach as upstream's open PR #586, written independently). | `services/deepwiki/patch_openai_stream.py` (contains the replaced upstream lines to locate them) |
| `src/app/[owner]/[repo]/slides/page.tsx`, `src/app/[owner]/[repo]/workshop/page.tsx` | WebSocket base URL `process.env.SERVER_BASE_URL \|\| 'http://localhost:8001'` → `window.location.origin` | `services/deepwiki/patch_ui.mjs` (contains the replaced upstream line) |

Build settings that upstream's code reads (not source changes): `NEXT_PUBLIC_API_PORT=443`, `SERVER_BASE_URL=http://127.0.0.1:8001`, `DEEPWIKI_CONFIG_DIR`, `DEEPWIKI_EMBEDDER_TYPE`, `DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS`, `LOG_FILE_PATH`.

## Verified against

| What | Upstream file / source | Ref | Checked |
|---|---|---|---|
| Container layout, processes, ports, env | `Dockerfile`, `docker-compose.yml`, `docker-compose-litellm.yml`, `.github/workflows/docker-build-push.yml` | `d92819a` | 2026-10-20 |
| Image contents | GHCR registry API: index/manifest/config of `sha-d92819a` (= `main` = `latest`, `sha256:730b7249…`), revision label, venv layer listing, `node_version.h` (Node 20.20.2) | built 2026-09-03 | 2026-10-20 |
| API routes, auth mode scope, health endpoint, uvicorn bind | `api/main.py`, `api/routers/*.py`, `api/config.py` | `d92819a` | 2026-10-20 |
| Storage paths | `api/utils.py`, `api/repository.py`, `api/rag/pipeline.py`, `api/services/wiki/*.py`; AdalFlow `get_adalflow_default_root_path` | `d92819a`; AdalFlow `main` | 2026-10-20 |
| Provider and embedder configuration | `api/config/generator.json`, `embedder.json`, `api/chat/_stream.py`, `api/clients/*.py` | `d92819a` | 2026-10-20 |
| OpenAI streaming bug | upstream issue #585, PR #586 (open); AdalFlow `openai_client.py` (Responses API only) | AdalFlow `v1.1.3` | 2026-10-20 |
| Browser WebSocket URLs, Next.js rewrites | `src/utils/websocketClient.ts`, slides/workshop pages, `next.config.ts`, `src/app/api/**` | `d92819a` | 2026-10-20 |
| Concurrency defaults | `api/services/wiki/tasks.py` | `d92819a` | 2026-10-20 |
| Model availability | developers.openai.com deprecations and models pages; ai.google.dev Gemini deprecations and models pages | — | 2026-10-20 |
| Security advisories | GitHub Advisory Database (`next`, `gitpython`, `sharp`) | — | 2026-10-20 |
| Caddy directives used | `modules/caddyhttp/caddyauth/caddyfile.go`, `command.go`, `modules/caddyhttp/matchers.go` | Caddy `v2.11.7` | 2026-10-20 |

The local `_upstream/AsyncFuncAI__deepwiki-open` copy equals commit `d92819a` (all 178 blob hashes compared); it was read, never executed (only copies of two TSX pages and `_stream.py` were used as inputs to test the patch scripts).

## Files in this template

All files were written for this template. Snippets of DeepWiki-Open code appear only inside the two patch scripts, as the exact lines they replace (MIT, attributed above).

| File | Notes |
|---|---|
| `services/deepwiki/Dockerfile` | Written for this template; follows the stage layout of upstream's MIT-licensed `Dockerfile` (Node build stage, Python runtime). |
| `services/deepwiki/start.sh`, `configure.py`, `Caddyfile` | Written for this template. |
| `services/deepwiki/patch_openai_stream.py`, `check_openai_stream.py`, `patch_ui.mjs` | Written for this template (see "Modifications"). |
| `services/deepwiki/security-requirements.txt` | GitPython pin with PyPI hash. |
| `TEMPLATE.md`, `template.json`, `README.md`, `NOTICE.md` | Written for this template. |

## Reference only (not copied)

- Marketplace template `deepwiki-open` ("DeepWiki-Open", image `ghcr.io/youssefsiam38/deepwiki-railway:1.0.0`, source repository without a license): its service config and README were read through Railway's public API for comparison. No files, text or image were used.

## Trademarks

"DeepWiki-Open" belongs to its authors; "OpenAI", "Gemini"/"Google", "OpenRouter", "Ollama", "GitHub", "GitLab", "Bitbucket" and "Railway" belong to their owners. This is a community template and is not affiliated with or endorsed by AsyncFuncAI, the deepwiki.com service, any LLM provider, or Railway.
