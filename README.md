# Deploy and Host DeepWiki-Open with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/deepwiki-open-ai-wiki-for-your-repos?referralCode=20H68q)

DeepWiki-Open is an open-source (MIT) tool that reads a GitHub, GitLab or Bitbucket repository and writes an interactive wiki about it: architecture pages, Mermaid diagrams and a chat that answers questions from the code. This community template runs it on one password-protected HTTPS URL with persistent storage.

## About Hosting DeepWiki-Open

DeepWiki-Open has a Next.js web interface and a Python (FastAPI) backend. The backend clones the repository you enter, splits and embeds its files, keeps the embeddings and generated wikis on disk, and calls your LLM provider for every page and answer. Upstream ships both parts in one container without a login and expects the browser to reach a second port. This template keeps the single container, adds a Caddy front door with HTTP basic auth and a generated password, serves the UI, API and WebSockets on one domain, stores clones, embeddings and wikis on a Railway volume, and pins upstream's image and source to one commit.

## Common Use Cases

- Onboarding: give new team members a readable overview and diagrams of an unfamiliar codebase
- Ask questions about a repository ("where is authentication handled?") and get answers grounded in its files
- Generate a first draft of internal documentation for private repositories, kept on your own Railway project
- Explore open-source projects before adopting or contributing to them

Generated pages are LLM output: useful as a starting point, but check them against the code before relying on them.

## Dependencies for DeepWiki-Open Hosting

- DeepWiki-Open image `ghcr.io/asyncfuncai/deepwiki-open` (upstream build, pinned by digest) with the web UI rebuilt from the same commit
- Caddy 2.11 as the login and routing layer (inside the same service)
- An LLM provider key: OpenAI (default; covers generation and embeddings), or Google Gemini, or OpenRouter plus an OpenAI/Gemini key for embeddings, or your own Ollama server
- A Railway volume (included) for cloned repositories, embeddings, generated wikis and logs

### Deployment Dependencies

- DeepWiki-Open source and issues: https://github.com/AsyncFuncAI/deepwiki-open
- DeepWiki-Open container image: https://github.com/AsyncFuncAI/deepwiki-open/pkgs/container/deepwiki-open
- OpenAI API keys: https://platform.openai.com/api-keys
- Google AI Studio (Gemini API keys): https://aistudio.google.com/apikey
- OpenRouter keys: https://openrouter.ai/keys
- GitHub fine-grained tokens (for private repositories): https://github.com/settings/personal-access-tokens
- Caddy basic auth: https://caddyserver.com/docs/caddyfile/directives/basic_auth

### Implementation Details

| Service | Built from | Role | Public |
|---|---|---|---|
| DeepWiki | upstream image `sha-d92819a` + UI rebuild + Caddy (`services/deepwiki`) | Login, web UI, API, WebSockets; volume at `/root/.adalflow` | **yes** |

**Before you deploy:** enter your OpenAI API key in `OPENAI_API_KEY`. To use Google Gemini instead, enter `none` there and put your Gemini key in `GOOGLE_API_KEY`. OpenRouter (`OPENROUTER_API_KEY`) and your own Ollama server (`OLLAMA_HOST`) are optional extras; OpenRouter cannot create embeddings, so it still needs an OpenAI or Gemini key next to it.

**First login**

1. Wait until the service is Active. The first build rebuilds the web UI, which takes a few minutes.
2. Open the service URL. Your browser asks for a user name and password: use `BASIC_AUTH_USERNAME` (default `admin`) and `BASIC_AUTH_PASSWORD` from the service variables.
3. Paste a repository URL (for example `https://github.com/AsyncFuncAI/deepwiki-open`), check the model in the settings dialog and generate the wiki. Progress is shown live; finished wikis appear on the start page.
4. For a private repository, add an access token in the same dialog. Use a fine-grained, read-only token. The token is sent with the clone request; this template removes it from the stored clone at the next restart.

**Models:** the UI preselects the provider of your key, with `gpt-6-luna` (OpenAI) or `gemini-3.8-flash` (Gemini) as the default model. Change the default with `DEEPWIKI_MODEL`, or pick another model per wiki in the UI. Embeddings use one model per deployment (`text-embedding-3-small` or `gemini-embedding-001`); after switching providers, regenerate existing wikis.

**Cost control:** every wiki page, chat answer and codemap is an LLM call billed by your provider, and indexing a repository sends its text to the embedding API once. Start with a small repository and watch your provider's usage page.

**Security:** DeepWiki-Open has no user accounts, so everything except the `/health` probe sits behind the basic-auth login, requests started by other websites are refused, and the UI and API listen on localhost inside the container. Share the login only with people you trust to spend your API credits. To change the password, edit `BASIC_AUTH_PASSWORD` and redeploy. `DEEPWIKI_AUTH_MODE` (off by default) only adds an extra code prompt in the UI; it is not a replacement for the login.

**Custom domain:** add it to the service in Railway; nothing else changes.

**Scaling:** run one replica (generation tasks live in the process and the volume belongs to one service). Give it more memory for large repositories: indexing holds a repository's chunks and embeddings in RAM. `DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS` limits how many wikis are generated at once (default: half the service's vCPUs). Redeploying stops running generations; finished wikis stay.

**Pinning and upgrading:** the upstream image is pinned by digest and the UI source by commit (`DEEPWIKI_SOURCE_COMMIT` in `services/deepwiki/Dockerfile`); change both together to the same upstream commit. Two small build-time patches (OpenAI streaming, slides/workshop WebSocket URL) refuse to apply if upstream changed that code, so an upgrade fails loudly instead of silently.

This is a community template. It is not made, endorsed or supported by the DeepWiki-Open authors (AsyncFuncAI) and is not related to the hosted deepwiki.com service.

### Why Deploy DeepWiki-Open on Railway?

Railway runs the container, the volume and the HTTPS domain for you, so a password-protected DeepWiki-Open is a single deploy instead of a reverse-proxy and storage setup on your own server. Your repositories, embeddings and wikis stay in your Railway project, you pay for the RAM and CPU it actually uses, and the LLM costs go straight to the provider you choose.
