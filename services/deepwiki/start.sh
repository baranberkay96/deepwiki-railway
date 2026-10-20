#!/bin/bash
# DeepWiki on Railway: checks the configuration, then runs three processes in one
# container (upstream ships the UI and API in one container too):
#   DeepWiki API (uvicorn)  127.0.0.1:8001   loopback only
#   Next.js UI              127.0.0.1:3000   loopback only
#   Caddy                   :$PORT (8080)    public; basic auth, /ws -> API, rest -> UI
# If any of them exits, the others are stopped and the container exits, so Railway
# restarts the whole service.
set -euo pipefail

log() { printf '[deepwiki] %s\n' "$*"; }
fail() { printf '[deepwiki] ERROR: %s\n' "$*" >&2; exit 1; }

APP_DIR="${DEEPWIKI_APP_DIR:-/app}"                 # overridable for local tests only
CADDYFILE="${DEEPWIKI_CADDYFILE:-/etc/caddy/Caddyfile}"
DATA_DIR="${HOME:-/root}/.adalflow"                 # upstream data root (~/.adalflow)
CONFIG_OUT="${DEEPWIKI_CONFIG_OUT:-/tmp/deepwiki-config}"
LOOPBACK=127.0.0.1
API_PORT=8001
UI_PORT=3000
PUBLIC_PORT="${PORT:-8080}"

# ---------------------------------------------------------------- keys -----
# "none" (or empty) means "not used": the Railway form needs a value for the one
# required key, so Gemini-only users enter none there.
for var in OPENAI_API_KEY GOOGLE_API_KEY OPENROUTER_API_KEY OLLAMA_HOST; do
  value="${!var:-}"
  case "$value" in
    ''|none|None|NONE|unused|-) unset "$var" ;;
    *[[:space:]]*) fail "$var contains whitespace; paste the key without spaces or line breaks" ;;
  esac
done

has() { [ -n "${!1:-}" ]; }

# ------------------------------------------------------- LLM provider -----
provider="${DEEPWIKI_PROVIDER:-auto}"
case "$provider" in
  auto|'')
    if has OPENAI_API_KEY; then provider=openai
    elif has GOOGLE_API_KEY; then provider=google
    elif has OPENROUTER_API_KEY; then provider=openrouter
    elif has OLLAMA_HOST; then provider=ollama
    else fail "no LLM provider configured: set OPENAI_API_KEY, GOOGLE_API_KEY, OPENROUTER_API_KEY or OLLAMA_HOST"
    fi ;;
  openai|google|openrouter|ollama|bedrock|azure|dashscope) ;;
  *) fail "DEEPWIKI_PROVIDER must be auto, openai, google, openrouter, ollama, bedrock, azure or dashscope (got '$provider')" ;;
esac

require_for_provider() {
  case "$1" in
    openai) has OPENAI_API_KEY || fail "DEEPWIKI_PROVIDER=openai needs OPENAI_API_KEY" ;;
    google) has GOOGLE_API_KEY || fail "DEEPWIKI_PROVIDER=google needs GOOGLE_API_KEY" ;;
    openrouter) has OPENROUTER_API_KEY || fail "DEEPWIKI_PROVIDER=openrouter needs OPENROUTER_API_KEY" ;;
    ollama) has OLLAMA_HOST || fail "DEEPWIKI_PROVIDER=ollama needs OLLAMA_HOST (URL of your Ollama server)" ;;
    bedrock) { has AWS_ACCESS_KEY_ID && has AWS_SECRET_ACCESS_KEY; } || log "warning: bedrock needs AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY" ;;
    azure) { has AZURE_OPENAI_API_KEY && has AZURE_OPENAI_ENDPOINT; } || log "warning: azure needs AZURE_OPENAI_API_KEY, AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_VERSION" ;;
    dashscope) has DASHSCOPE_API_KEY || log "warning: dashscope needs DASHSCOPE_API_KEY" ;;
  esac
}
require_for_provider "$provider"

# ------------------------------------------------------------ embedder -----
# One embedder per deployment (upstream DEEPWIKI_EMBEDDER_TYPE). Indexes built with
# one embedder cannot be queried with another.
embedder="${DEEPWIKI_EMBEDDER_TYPE:-}"
if [ -z "$embedder" ] || [ "$embedder" = auto ]; then
  case "$provider" in
    google) embedder=google ;;
    ollama) embedder=ollama ;;
    bedrock) embedder=bedrock ;;
    *) if has OPENAI_API_KEY; then embedder=openai
       elif has GOOGLE_API_KEY; then embedder=google
       elif has OLLAMA_HOST; then embedder=ollama
       else fail "embeddings need OPENAI_API_KEY, GOOGLE_API_KEY or OLLAMA_HOST (OpenRouter has no embedding support in DeepWiki)"
       fi ;;
  esac
fi
case "$embedder" in
  openai) has OPENAI_API_KEY || fail "DEEPWIKI_EMBEDDER_TYPE=openai needs OPENAI_API_KEY" ;;
  google) has GOOGLE_API_KEY || fail "DEEPWIKI_EMBEDDER_TYPE=google needs GOOGLE_API_KEY" ;;
  ollama) has OLLAMA_HOST || fail "DEEPWIKI_EMBEDDER_TYPE=ollama needs OLLAMA_HOST" ;;
  bedrock) ;;
  *) fail "DEEPWIKI_EMBEDDER_TYPE must be empty/auto, openai, google, ollama or bedrock (got '$embedder')" ;;
esac
export DEEPWIKI_EMBEDDER_TYPE="$embedder"

# ------------------------------------------------------------- threads -----
# FAISS/numpy size their thread pools from the host's cores, not the service's CPU
# quota (Railway hosts have dozens of cores). Use the cgroup quota, max 8.
threads="${DEEPWIKI_CPU_THREADS:-}"
if [ -z "$threads" ]; then
  threads=""
  if read -r quota period 2>/dev/null < /sys/fs/cgroup/cpu.max \
     && [ "$quota" != max ] && [ "${period:-0}" -gt 0 ] 2>/dev/null; then
    threads=$(( (quota + period - 1) / period ))
  fi
  [ -n "$threads" ] || threads="$(nproc 2>/dev/null || echo 2)"
  [ "$threads" -ge 1 ] || threads=1
  [ "$threads" -le 8 ] || threads=8
fi
case "$threads" in
  ''|*[!0-9]*|0) fail "DEEPWIKI_CPU_THREADS must be a positive integer (got '$threads')" ;;
esac
export OMP_NUM_THREADS="$threads" OPENBLAS_NUM_THREADS="$threads" \
  MKL_NUM_THREADS="$threads" NUMEXPR_NUM_THREADS="$threads"

# Upstream runs up to cpu_count()/2 wiki tasks at once (48 on a 96-core host), each
# cloning and indexing a repository in memory. Default to half the CPU quota.
wiki_tasks="${DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS:-}"
[ -n "$wiki_tasks" ] || wiki_tasks=$(( threads > 2 ? threads / 2 : 1 ))
case "$wiki_tasks" in
  ''|*[!0-9]*|0) fail "DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS must be a positive integer (got '$wiki_tasks')" ;;
esac
export DEEPWIKI_MAX_CONCURRENT_WIKI_TASKS="$wiki_tasks"

# --------------------------------------------------------------- login -----
: "${BASIC_AUTH_USERNAME:?BASIC_AUTH_USERNAME must be set}"
: "${BASIC_AUTH_PASSWORD:?BASIC_AUTH_PASSWORD must be set}"
case "$BASIC_AUTH_USERNAME" in
  *[!A-Za-z0-9._@-]*) fail "BASIC_AUTH_USERNAME may only contain letters, digits and . _ @ -" ;;
esac
[ "${#BASIC_AUTH_PASSWORD}" -ge 12 ] || fail "BASIC_AUTH_PASSWORD must be at least 12 characters"
case "$BASIC_AUTH_PASSWORD" in
  *$'\n'*) fail "BASIC_AUTH_PASSWORD must be a single line" ;;
esac
auth_code="${DEEPWIKI_AUTH_CODE:-}"
case "${DEEPWIKI_AUTH_MODE:-false}" in
  true|True|TRUE|1|t|T)
    [ "${#auth_code}" -ge 8 ] || fail "DEEPWIKI_AUTH_MODE is on: set DEEPWIKI_AUTH_CODE (8+ characters)" ;;
esac
unset auth_code

# Caddy needs a bcrypt hash; the password goes over stdin, never on a command line.
BASIC_AUTH_HASH="$(printf '%s\n' "$BASIC_AUTH_PASSWORD" | caddy hash-password --algorithm bcrypt)"
case "$BASIC_AUTH_HASH" in '$2'*) ;; *) fail "could not hash BASIC_AUTH_PASSWORD" ;; esac
# WebSocket session cookie value: derived from the password, so it survives
# redeploys and changes when the password changes.
WS_SESSION_TOKEN="$(printf 'deepwiki-ws-session\n%s' "$BASIC_AUTH_PASSWORD" | sha256sum | cut -c1-64)"
export BASIC_AUTH_HASH WS_SESSION_TOKEN
unset BASIC_AUTH_PASSWORD

# --------------------------------------------------------------- data ------
mkdir -p "$DATA_DIR" "$DATA_DIR/logs"
if ! awk -v d="$DATA_DIR" '$5 == d { found = 1 } END { exit !found }' /proc/self/mountinfo; then
  log "warning: $DATA_DIR is not a mounted volume; wikis, clones and embeddings are lost on redeploy"
fi
# Upstream clones private repos with the access token in the remote URL, which git
# keeps in .git/config on the volume. Strip it (clones are never fetched again).
scrubbed=0
for cfg in "$DATA_DIR"/repo/*/.git/config; do
  [ -f "$cfg" ] || continue
  if grep -Eq 'url = [a-z]+://[^/@[:space:]]+@' "$cfg"; then
    sed -i -E 's#(url = [a-z]+://)[^/@[:space:]]+@#\1#' "$cfg"
    scrubbed=$((scrubbed + 1))
  fi
done
[ "$scrubbed" -eq 0 ] || log "removed stored access tokens from $scrubbed cloned repositories"

export LOG_FILE_PATH="${LOG_FILE_PATH:-$DATA_DIR/logs/application.log}"

# -------------------------------------------------------------- config -----
python "$APP_DIR/railway/configure.py" "$APP_DIR/api/config" "$CONFIG_OUT" "$provider" "${DEEPWIKI_MODEL:-}"
export DEEPWIKI_CONFIG_DIR="$CONFIG_OUT"

# Backend address for the Next.js server routes (rewrites were fixed at build time).
export SERVER_BASE_URL="http://$LOOPBACK:$API_PORT"
export PYTHON_BACKEND_HOST="$SERVER_BASE_URL"
export NODE_ENV=production

log "provider=$provider embedder=$embedder threads=$threads wiki_tasks=$wiki_tasks login user=\"$BASIC_AUTH_USERNAME\" auth_code=${DEEPWIKI_AUTH_MODE:-false} data=$DATA_DIR public port=$PUBLIC_PORT"

# ----------------------------------------------------------- processes -----
pids=()
stop_all() {
  trap - TERM INT
  log "stopping"
  kill -TERM "${pids[@]}" 2>/dev/null || true
  wait "${pids[@]}" 2>/dev/null || true
}
trap 'stop_all; exit 0' TERM INT

cd "$APP_DIR"
python -m uvicorn api.main:app --host "$LOOPBACK" --port "$API_PORT" \
  --timeout-graceful-shutdown 10 --no-server-header &
pids+=($!)

PORT="$UI_PORT" HOSTNAME="$LOOPBACK" node server.js &
pids+=($!)

caddy run --config "$CADDYFILE" --adapter caddyfile &
pids+=($!)

set +e
wait -n "${pids[@]}"
status=$?
set -e
log "a process exited (status $status); stopping the others"
stop_all
exit "$(( status == 0 ? 1 : status ))"
