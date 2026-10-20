# DeepWiki Open for Railway: upstream's published image (Python API + Next.js UI)
# with the UI rebuilt for a single HTTPS domain, a fix for OpenAI streaming, and
# Caddy in front for login and routing.
#
# Upgrade: change DEEPWIKI_SOURCE_COMMIT below AND the upstream image digest in the
# final stage together (the image's org.opencontainers.image.revision label must
# equal the commit). Then check whether patch_openai_stream.py and patch_ui.mjs
# are still needed (both stop the build if the code they patch has changed).

# ---------------------------------------------------------------- UI build ----
# Same Node.js release as the upstream runtime (20.20.2, Debian trixie), so the
# traced node_modules (e.g. sharp's glibc binary) match the runtime.
FROM node:20.20.2-trixie-slim@sha256:abfbe12cc943141a0c9e8c0a57d710df1dadd95d35e8662cc02958b284d1f35b AS ui

ARG DEEPWIKI_SOURCE_REPO=https://github.com/AsyncFuncAI/deepwiki-open.git
ARG DEEPWIKI_SOURCE_COMMIT=d92819a9c9f3b99416e3580ff235fc9d3adf8b89

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN set -eux; \
    git init -q .; \
    git fetch -q --depth 1 "$DEEPWIKI_SOURCE_REPO" "$DEEPWIKI_SOURCE_COMMIT"; \
    git -c advice.detachedHead=false checkout -q FETCH_HEAD; \
    test "$(git rev-parse HEAD)" = "$DEEPWIKI_SOURCE_COMMIT"

# Slides/workshop pages: WebSocket to the page's own origin instead of the
# visitor's localhost:8001 (see patch_ui.mjs).
COPY patch_ui.mjs /tmp/patch_ui.mjs
RUN node /tmp/patch_ui.mjs

# NEXT_PUBLIC_* values are compiled into the browser bundle:
# - upstream's chat/codemap WebSocket client connects to <page host>:<NEXT_PUBLIC_API_PORT>
#   (default 8001, which Railway does not expose). 443 = the page's own HTTPS port,
#   where Caddy forwards /ws/* to the API.
# SERVER_BASE_URL is read by next.config.ts rewrites at build time.
ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_OPTIONS=--max-old-space-size=4096 \
    NEXT_PUBLIC_API_PORT=443 \
    SERVER_BASE_URL=http://127.0.0.1:8001

# next 15.5.22 (upstream lock) has critical advisories GHSA-2xp9-vwfh-vxw4 and
# GHSA-p293-qw3h-jr36 (fixed 15.5.24) and two medium ones (fixed 15.5.27).
# 15.5.27 is inside upstream's declared range (^15.5.22). Caddy also blocks
# /_next/image, the endpoint of the critical one.
RUN set -eux; \
    npm ci --legacy-peer-deps --no-audit --no-fund; \
    npm install --no-save --legacy-peer-deps --no-audit --no-fund next@15.5.27; \
    test "$(node -p 'require("next/package.json").version')" = 15.5.27; \
    NODE_ENV=production npm run build; \
    test -f .next/standalone/server.js; \
    grep -rq '127.0.0.1:8001' .next/routes-manifest.json

# ------------------------------------------------------------------ runtime ---
FROM caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f AS caddy

# ghcr.io/asyncfuncai/deepwiki-open:sha-d92819a (= main = latest on 2026-10-20),
# built 2026-09-03 from commit d92819a9c9f3b99416e3580ff235fc9d3adf8b89.
FROM ghcr.io/asyncfuncai/deepwiki-open:sha-d92819a@sha256:730b72494f407397c896c586af0a31af9671d509af420e6792d834ff094a9c8f

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy

# Replace upstream's prebuilt UI (it points the browser's WebSockets at port 8001).
RUN rm -rf /app/.next /app/node_modules /app/server.js /app/package.json /app/public
COPY --from=ui /src/public /app/public
COPY --from=ui /src/.next/standalone /app/
COPY --from=ui /src/.next/static /app/.next/static

# GitPython security update (see security-requirements.txt) and the OpenAI
# streaming fix (upstream issue #585), verified with fake stream events.
COPY security-requirements.txt patch_openai_stream.py check_openai_stream.py /tmp/railway/
RUN set -eux; \
    python -m pip install --no-cache-dir --no-deps --require-hashes -r /tmp/railway/security-requirements.txt; \
    test "$(python -c 'import git; print(git.__version__)')" = 3.1.61; \
    python /tmp/railway/patch_openai_stream.py /app/api/chat/_stream.py; \
    python -m py_compile /app/api/chat/_stream.py; \
    cd /app && python /tmp/railway/check_openai_stream.py; \
    python -c "import api.main" >/dev/null; \
    rm -rf /tmp/railway /root/.adalflow /app/api/logs

COPY Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0755 start.sh /app/railway/start.sh
COPY configure.py /app/railway/configure.py

# Validate the Caddy config with placeholder values (real ones come at start).
RUN BASIC_AUTH_USERNAME=check \
    BASIC_AUTH_HASH='$2a$14$abcdefghijklmnopqrstuuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0' \
    WS_SESSION_TOKEN=0000000000000000000000000000000000000000000000000000000000000000 \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
    && python /app/railway/configure.py /app/api/config /tmp/config-check openai \
    && python /app/railway/configure.py /app/api/config /tmp/config-check google \
    && rm -rf /tmp/config-check

ENV HOME=/root \
    PORT=8080 \
    NODE_ENV=production \
    SERVER_BASE_URL=http://127.0.0.1:8001 \
    PYTHON_BACKEND_HOST=http://127.0.0.1:8001

EXPOSE 8080
WORKDIR /app
CMD ["/app/railway/start.sh"]
