#!/usr/bin/env bash
# Start (or reuse) an agent's container for this project and open a bash shell in it.
# Run it from YOUR clone, on the laptop and on the server:
#
#   ~/repo/<repo>/.devcontainer/up.sh                    # agent "agent": start, or another shell
#   ~/repo/<repo>/.devcontainer/up.sh agent-2            # a second agent, own clone and container
#   ~/repo/<repo>/.devcontainer/up.sh --rebuild [name]   # after a change to the kit or
#                                                        # .devcontainer-domains
#   ~/repo/<repo>/.devcontainer/up.sh --reset-env [name] # rebuild the agent's conda env from scratch
#
# The conda env lives in a volume and is built at container start when environment.yml changes
# (post-start.sh), so a dependency change needs no rebuild.
#
# The image is built from your clone. Each agent works in its own clone,
# ~/workspaces/<repo>/<name>, made here on its first run; your clone fetches it as remote <name>.
# On the host, only ever fetch from those clones (see README.md).
#
# On a host with an NVIDIA GPU the env gets CUDA builds of conda packages. Override with
# CLAUDE_DEV_CUDA=<version>, or CLAUDE_DEV_CUDA= (empty) for a CPU build.
set -euo pipefail
KIT=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$KIT")
REPO=$(basename "$ROOT")
NAME=agent
UP_ARGS=()
RESET_ENV=no
for arg in "$@"; do
  case $arg in
    --rebuild) UP_ARGS=(--remove-existing-container) ;;
    --reset-env) RESET_ENV=yes ;;
    -*) echo "Usage: up.sh [--rebuild] [--reset-env] [name]" >&2; exit 1 ;;
    *) NAME=$arg ;;
  esac
done
[[ $NAME =~ ^[A-Za-z0-9_-]+$ ]] || { echo "ERROR: bad agent name: $NAME" >&2; exit 1; }
WS=$HOME/workspaces/$REPO/$NAME
SECRETS=$HOME/.config/claude-dev
# devcontainer.json keys mounts and volumes on these, not on the workspace folder's name.
export CLAUDE_DEV_REPO=$REPO CLAUDE_DEV_NAME=$NAME

for f in environment.yml .devcontainer-domains; do
  [ -f "$ROOT/$f" ] || { echo "ERROR: $ROOT has no $f" >&2; exit 1; }
done

# Host directories the container mounts.
mkdir -p "$HOME/workspaces/$REPO" "$HOME/data/$REPO" "$SECRETS/shared" "$SECRETS/repos/$REPO"
chmod 700 "$SECRETS" "$SECRETS/shared" "$SECRETS/repos" "$SECRETS/repos/$REPO"
[ -s "$SECRETS/repos/$REPO/gh-token" ] || echo "NOTE: no $SECRETS/repos/$REPO/gh-token: git cannot reach GitHub from the container" >&2
[ -s "$SECRETS/shared/hf-token" ]      || echo "NOTE: no $SECRETS/shared/hf-token: Hugging Face downloads are anonymous" >&2
[ -s "$SECRETS/shared/netrc" ]         || echo "NOTE: no $SECRETS/shared/netrc: no W&B logging" >&2

# The agent's clone, made once, set up before Claude ever touches it. Origin is GitHub over
# HTTPS (the container's read-only token); pushing is disabled. A local-only project (your
# clone has no origin) gives the agent no origin either.
if [ ! -d "$WS" ]; then
  git clone --no-hardlinks --recurse-submodules "$ROOT" "$WS"
  # A container left over from an earlier clone at this path mounts a deleted directory.
  old=$(docker ps -aq --filter "label=devcontainer.local_folder=$WS")
  [ -z "$old" ] || { echo "Removing stale container for $WS"; docker rm -f $old >/dev/null; }
  if url=$(git -C "$ROOT" remote get-url origin 2>/dev/null); then
    url=$(echo "$url" | sed -E 's#^(ssh://)?git@github\.com[:/]#https://github.com/#')
    git -C "$WS" remote set-url origin "$url"
    git -C "$WS" remote set-url --push origin DISABLED
  else
    git -C "$WS" remote remove origin
  fi
  # Instructions for this machine: server if it has an NVIDIA GPU, else laptop.
  if nvidia-smi -L >/dev/null 2>&1; then m=server; else m=local; fi
  echo "@.devcontainer/claude/$m.md" > "$WS/CLAUDE.local.md"
  echo "Made $WS ($m machine)"
fi
# Your clone fetches the agent's commits from remote <name>.
if ! remote=$(git -C "$ROOT" remote get-url "$NAME" 2>/dev/null); then
  git -C "$ROOT" remote add "$NAME" "$WS"
  git -C "$ROOT" config "remote.$NAME.tagOpt" --no-tags
elif [ "$remote" != "$WS" ]; then
  echo "WARNING: remote $NAME in $ROOT is $remote, not $WS" >&2
fi

if [ -z "${CLAUDE_DEV_CUDA+set}" ] && nvidia-smi -L >/dev/null 2>&1; then
  CLAUDE_DEV_CUDA=$(nvidia-smi | sed -n 's/.*CUDA Version: *\([0-9.]*\).*/\1/p' | head -1)
  export CLAUDE_DEV_CUDA
fi
if [ -n "${CLAUDE_DEV_CUDA:-}" ]; then echo "CUDA build ($CLAUDE_DEV_CUDA)"; else echo "CPU build"; fi
CLAUDE_CODE_VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo latest)
export CLAUDE_CODE_VERSION

# The env volume is in use while the container exists, so remove the container first.
if [ $RESET_ENV = yes ]; then
  c=$(docker ps -aq --filter "label=devcontainer.local_folder=$WS")
  [ -z "$c" ] || docker rm -f $c >/dev/null
  docker volume rm "claude-dev-env-$REPO-$NAME" >/dev/null 2>&1 || true
  echo "Removed env volume claude-dev-env-$REPO-$NAME: the start rebuilds the env"
fi

DC=(--workspace-folder "$WS" --config "$KIT/devcontainer.json")
devcontainer up "${DC[@]}" "${UP_ARGS[@]}"
exec devcontainer exec "${DC[@]}" bash
