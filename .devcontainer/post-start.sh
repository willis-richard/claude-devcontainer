#!/usr/bin/env bash
# Runs in the container, as node in /workspace, at every start (postStartCommand). It is baked
# into the image, so the copy in Claude's clone never runs.
set -euo pipefail
sudo /usr/local/bin/init-firewall.sh

# Editable install of the project. Not in environment.yml: the image build sees only that file.
# --no-deps: environment.yml owns the dependencies. --no-build-isolation: the build backend
# (setuptools) comes from the env, so this needs no download.
if [ -f pyproject.toml ] || [ -f setup.py ]; then
  pip install --quiet --no-deps --no-build-isolation -e . \
    || echo "WARNING: editable install of the project failed" >&2
fi

# The image's build (CPU or CUDA) must match the GPU this container can see.
if nvidia-smi -L >/dev/null 2>&1; then gpu=yes; else gpu=no; fi
if [ -n "${IMAGE_CUDA_VERSION:-}" ] && [ $gpu = no ]; then
  echo "ERROR: CUDA image (CUDA $IMAGE_CUDA_VERSION) but no GPU in this container." >&2
  echo "       Run nvidia-smi on the host; if it works there, run up.sh --rebuild." >&2
  exit 1
fi
if [ -z "${IMAGE_CUDA_VERSION:-}" ] && [ $gpu = yes ]; then
  echo "ERROR: GPU visible but this is a CPU image. Run up.sh --rebuild." >&2
  exit 1
fi
echo "Image: ${IMAGE_CUDA_VERSION:+CUDA }${IMAGE_CUDA_VERSION:-CPU}, GPU visible: $gpu"
