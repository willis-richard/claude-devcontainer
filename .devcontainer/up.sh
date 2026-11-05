#!/usr/bin/env bash
# Start (or reuse) the container for this project and attach to tmux session "main" in it.
# Run it from YOUR clone, on the laptop and on the server:
#
#   ~/repo/<repo>/.devcontainer/up.sh             # start, or reattach
#   ~/repo/<repo>/.devcontainer/up.sh --rebuild   # after a change to the kit, environment.yml
#                                                 # or .devcontainer-domains
#
# The image is built from your clone. Claude works in its own clone, ~/workspaces/<repo>, made
# here on the first run. On the host, only ever fetch from that clone (see README.md).
# Detach with Ctrl-b d; work in tmux keeps running.
#
# On a host with an NVIDIA GPU the image gets CUDA builds of conda packages. Override with
# CLAUDE_DEV_CUDA=<version>, or CLAUDE_DEV_CUDA= (empty) for a CPU build.
set -euo pipefail
KIT=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$KIT")
REPO=$(basename "$ROOT")
WS=$HOME/workspaces/$REPO
SECRETS=$HOME/.config/claude-dev
UP_ARGS=()
[ "${1:-}" = "--rebuild" ] && UP_ARGS=(--remove-existing-container)

for f in environment.yml .devcontainer-domains; do
  [ -f "$ROOT/$f" ] || { echo "ERROR: $ROOT has no $f" >&2; exit 1; }
done

# Host directories the container mounts.
mkdir -p "$HOME/data/$REPO" "$SECRETS/shared" "$SECRETS/repos/$REPO"
chmod 700 "$SECRETS" "$SECRETS/shared" "$SECRETS/repos" "$SECRETS/repos/$REPO"
[ -s "$SECRETS/repos/$REPO/gh-token" ] || echo "NOTE: no $SECRETS/repos/$REPO/gh-token: git cannot reach GitHub from the container" >&2
[ -s "$SECRETS/shared/hf-token" ]      || echo "NOTE: no $SECRETS/shared/hf-token: Hugging Face downloads are anonymous" >&2
[ -s "$SECRETS/shared/netrc" ]         || echo "NOTE: no $SECRETS/shared/netrc: no W&B logging" >&2

# Claude's clone, made once, set up before Claude ever touches it. Origin is GitHub over
# HTTPS (the container's read-only token); pushing is disabled.
if [ ! -d "$WS" ]; then
  url=$(git -C "$ROOT" remote get-url origin | sed -E 's#^(ssh://)?git@github\.com[:/]#https://github.com/#')
  git clone --no-hardlinks "$ROOT" "$WS"
  git -C "$WS" remote set-url origin "$url"
  git -C "$WS" remote set-url --push origin DISABLED
  # Instructions for this machine: server if it has an NVIDIA GPU, else laptop.
  if nvidia-smi -L >/dev/null 2>&1; then m=server; else m=local; fi
  echo "@.devcontainer/claude/$m.md" > "$WS/CLAUDE.local.md"
  echo "Made $WS ($m machine)"
fi
# Your clone fetches Claude's commits from remote "agent".
if ! git -C "$ROOT" remote get-url agent >/dev/null 2>&1; then
  git -C "$ROOT" remote add agent "$WS"
  git -C "$ROOT" config remote.agent.tagOpt --no-tags
fi

if [ -z "${CLAUDE_DEV_CUDA+set}" ] && nvidia-smi -L >/dev/null 2>&1; then
  CLAUDE_DEV_CUDA=$(nvidia-smi | sed -n 's/.*CUDA Version: *\([0-9.]*\).*/\1/p' | head -1)
  export CLAUDE_DEV_CUDA
fi
if [ -n "${CLAUDE_DEV_CUDA:-}" ]; then echo "CUDA build ($CLAUDE_DEV_CUDA)"; else echo "CPU build"; fi
CLAUDE_CODE_VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo latest)
export CLAUDE_CODE_VERSION

DC=(--workspace-folder "$WS" --config "$KIT/devcontainer.json")
devcontainer up "${DC[@]}" "${UP_ARGS[@]}"
exec devcontainer exec "${DC[@]}" tmux new -A -s main
