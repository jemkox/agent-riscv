#!/bin/sh
# Install the CPU agent harness for the current user (no root needed).
#
#   agent/install.sh [--workspace DIR] [--model-url URL] [--model-id ID] [--model-cmd CMD]
#                    [--context TOKENS] [--done-mark TEXT] [--no-systemd]
#
#   --workspace  the only folder the agent's sandbox may write; must contain this repo
#                (default: ~/agent-workspace if the repo is inside it, else the repo's parent folder)
#   --model-url  OpenAI-compatible model server with GET /health (default http://127.0.0.1:8080)
#   --model-id   model name the server expects (default local-model)
#   --model-cmd  command that starts the model server, run by cpu-agent-model.service (default: none,
#                you start the server yourself), e.g. "llama-server -m model.gguf --port 8080 -c 131072"
#   --context    the model's context window in tokens (default 131072)
#
# Files go to ~/.local/bin, ~/.config/opencode, ~/.config/systemd/user and ~/.config/cpu-agent. A file that
# already exists with different content is kept as <file>.before-cpu-agent first. Nothing is started.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd -P)
PROJECT=$(cd "$HERE/.." && pwd -P)
WORKSPACE=""; MODEL_URL="http://127.0.0.1:8080"; MODEL_ID="local-model"; MODEL_CMD=""
CONTEXT=131072; DONE_MARK="DOOM CPU: DONE"; SYSTEMD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE=$2; shift 2 ;;
    --model-url) MODEL_URL=${2%/}; shift 2 ;;
    --model-id)  MODEL_ID=$2; shift 2 ;;
    --model-cmd) MODEL_CMD=$2; shift 2 ;;
    --context)   CONTEXT=$2; shift 2 ;;
    --done-mark) DONE_MARK=$2; shift 2 ;;
    --no-systemd) SYSTEMD=0; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown option $1 (see --help)" >&2; exit 2 ;;
  esac
done
if [ -z "$WORKSPACE" ]; then
  case "$PROJECT/" in "$HOME/agent-workspace/"*) WORKSPACE="$HOME/agent-workspace" ;; *) WORKSPACE=$(dirname "$PROJECT") ;; esac
fi
mkdir -p "$WORKSPACE"; WORKSPACE=$(cd "$WORKSPACE" && pwd -P)
case "$PROJECT/" in "$WORKSPACE/"*) ;; *) echo "the repo ($PROJECT) must be inside the workspace ($WORKSPACE)" >&2; exit 1 ;; esac
case "$CONTEXT" in ''|*[!0-9]*) echo "--context must be a number of tokens" >&2; exit 2 ;; esac
INPUT=$((CONTEXT - 16384))

missing=""
for c in opencode bwrap python3 curl git; do command -v "$c" >/dev/null 2>&1 || missing="$missing $c"; done
[ -z "$missing" ] || echo "warning: not found:$missing (needed at run time; opencode: https://opencode.ai)" >&2

# install SRC DEST [MODE]: copy with placeholders filled in, keeping a changed existing file as a backup
esc() { printf '%s' "$1" | sed 's/[|&\\]/\\&/g'; }
install_file() {
  tmp=$(mktemp)
  sed -e "s|@WORKSPACE@|$(esc "$WORKSPACE")|g" -e "s|@PROJECT@|$(esc "$PROJECT")|g" \
      -e "s|@MODEL_URL@|$(esc "$MODEL_URL")|g" -e "s|@MODEL_ID@|$(esc "$MODEL_ID")|g" \
      -e "s|@CONTEXT@|$CONTEXT|g" -e "s|@INPUT@|$INPUT|g" -e "s|@DONE_MARK@|$(esc "$DONE_MARK")|g" "$1" > "$tmp"
  mkdir -p "$(dirname "$2")"
  if [ -f "$2" ] && ! cmp -s "$tmp" "$2"; then cp -p "$2" "$2.before-cpu-agent"; echo "  kept old $2 as $2.before-cpu-agent"; fi
  mv "$tmp" "$2"; chmod "${3:-644}" "$2"
  echo "  $2"
}

echo "Installing the CPU agent harness (workspace $WORKSPACE, project $PROJECT)"
for f in agent-watchdog cpu-agent cpu-agent-serve hdl model-up review-at-commit; do
  install_file "$HERE/bin/$f" "$HOME/.local/bin/$f" 755
done
OC="$HOME/.config/opencode"
install_file "$HERE/opencode/opencode.json.template" "$OC/opencode.json"
install_file "$HERE/opencode/AGENTS.md" "$OC/AGENTS.md"
install_file "$HERE/opencode/agent/cpu.md" "$OC/agent/cpu.md"
install_file "$HERE/opencode/agent/review.md" "$OC/agent/review.md"
install_file "$HERE/opencode/plugin/cpu-loop.js" "$OC/plugin/cpu-loop.js"
for u in cpu-agent-model cpu-agent-server cpu-agent-watchdog cpu-agent-reviewer; do
  install_file "$HERE/systemd/$u.service" "$HOME/.config/systemd/user/$u.service"
done
install_file "$HERE/reviews/REVIEW_PROMPT.md" "$WORKSPACE/reviews/REVIEW_PROMPT.md"
mkdir -p "$WORKSPACE/.agent-logs"

# Settings: keep the builder session of an earlier install so the agent continues where it was.
CA="$HOME/.config/cpu-agent"; mkdir -p "$CA"
old_session=$(sed -n 's/^SESSION="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$CA/config" 2>/dev/null | head -n 1)
[ -f "$CA/config" ] && cp -p "$CA/config" "$CA/config.before-cpu-agent"
qq() { printf '%s' "$1" | sed 's/["\\$`]/\\&/g'; }
cat > "$CA/config" <<EOF
# cpu-agent settings (agent/install.sh). Plain KEY="value" lines, read by every script and the plugin.
WORKSPACE="$(qq "$WORKSPACE")"
PROJECT="$(qq "$PROJECT")"
SESSION="${old_session:-}"
DONE_MARK="$(qq "$DONE_MARK")"
MODEL_URL="$(qq "$MODEL_URL")"
MODEL_CMD="$(qq "$MODEL_CMD")"
SERVER_PORT="4096"
EOF
echo "  $CA/config"
if [ ! -f "$CA/env" ]; then
  ( umask 077; echo 'MODEL_API_KEY=local   # API key the model server expects (any value for a local server)' > "$CA/env" )
  echo "  $CA/env"
fi

if [ "$SYSTEMD" = 1 ] && command -v systemctl >/dev/null 2>&1; then systemctl --user daemon-reload || true; fi
cat <<EOF

Done. Next:
  1. Make sure ~/.local/bin is on your PATH and a model server answers at $MODEL_URL/health
     (or set MODEL_CMD in $CA/config so cpu-agent starts it).
  2. cpu-agent start      # starts everything; the first start creates the builder session
     cpu-agent activity   # watch what it does;   cpu-agent stop   # stop it
Phone notifications (optional): put an ntfy.sh topic name in $CA/ntfy-topic.
EOF
