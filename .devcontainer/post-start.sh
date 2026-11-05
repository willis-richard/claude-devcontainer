#!/usr/bin/env bash
# Runs in the container, as node in /workspace, at every start (postStartCommand). It is baked
# into the image, so the copy in Claude's clone never runs.
set -euo pipefail
sudo /usr/local/bin/init-firewall.sh

# CONDA_OVERRIDE_CUDA (from up.sh via devcontainer.json) must match the GPU this container
# can see: it decides whether the env gets CPU or CUDA builds.
cuda=${CONDA_OVERRIDE_CUDA:-}
if nvidia-smi -L >/dev/null 2>&1; then gpu=yes; else gpu=no; fi
if [ -n "$cuda" ] && [ $gpu = no ]; then
  echo "ERROR: CUDA container (CUDA $cuda) but no GPU in this container." >&2
  echo "       Run nvidia-smi on the host; if it works there, run up.sh --rebuild." >&2
  exit 1
fi
if [ -z "$cuda" ] && [ $gpu = yes ]; then
  echo "ERROR: GPU visible but this is a CPU container. Run up.sh --rebuild." >&2
  exit 1
fi

# The env `dev` lives in a volume, so it survives rebuilds. Build it only when environment.yml
# or the CUDA target differs from the last successful build, recorded in the stamp.
envdir=$HOME/miniforge3/envs/dev
stamp=$HOME/miniforge3/envs/.dev-stamp
if [ -f environment.yml ]; then
  want="$(sha256sum < environment.yml | cut -d' ' -f1) cuda=$cuda"
  have=$(cat "$stamp" 2>/dev/null || true)
  if [ "$have" != "$want" ]; then
    # A new CUDA target (or no stamp: a failed first build) needs a fresh env: an update
    # would keep the old CPU or CUDA builds.
    if [ -d "$envdir" ] && [ "${have#* }" != "cuda=$cuda" ]; then rm -rf "$envdir"; fi
    if [ -d "$envdir" ]; then op=(update --prune); else op=(create); fi
    echo "environment.yml changed: conda env ${op[*]} -n dev"
    if conda env "${op[@]}" -n dev -f environment.yml; then
      echo "$want" > "$stamp"
    else
      echo "WARNING: building env dev failed; fix environment.yml and restart" >&2
    fi
    if [ -n "$cuda" ] && conda list -n dev --json 2>/dev/null \
        | jq -e '.[] | select(.name == "pytorch" and (.build_string | test("cpu")))' >/dev/null; then
      echo "ERROR: CPU build of pytorch in a CUDA container; check environment.yml" >&2
    fi
  fi
else
  echo "WARNING: no environment.yml: env dev not built" >&2
fi

# Editable install of the project. Not in environment.yml: it needs the project's source.
# --no-deps: environment.yml owns the dependencies. --no-build-isolation: the build backend
# (setuptools) comes from the env, so this needs no download.
if [ -d "$envdir" ] && { [ -f pyproject.toml ] || [ -f setup.py ]; }; then
  pip install --quiet --no-deps --no-build-isolation -e . \
    || echo "WARNING: editable install of the project failed" >&2
fi
echo "Env: ${cuda:+CUDA }${cuda:-CPU}, GPU visible: $gpu"
