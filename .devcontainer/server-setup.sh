#!/usr/bin/env bash
# One-time setup of a GPU server (Ubuntu with an NVIDIA driver and Docker, e.g. an AWS
# Deep Learning AMI). Per machine, not per project: up.sh does the per-project setup.
#
#   .devcontainer/server-setup.sh                  # Docker GPU check, devcontainer CLI
#   .devcontainer/server-setup.sh --idle-stop 60   # also shut down after 60 idle minutes
#
# Idle stop is for cloud instances, where shutting down = Stop (no GPU billing, disk kept).
# Don't use it on a machine where a shutdown is a problem. Safe to re-run.
set -euo pipefail
IDLE_MIN=""
[ "${1:-}" = "--idle-stop" ] && IDLE_MIN=${2:?minutes}

# 1. Driver
if ! nvidia-smi -L; then
  echo "ERROR: nvidia-smi failed: no NVIDIA GPU or driver on this host." >&2
  exit 1
fi

# 2. Docker, with GPU access
if ! id -nG | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  echo "Added $USER to the docker group. Log out, log back in, and re-run."
  exit 1
fi
docker run --rm --gpus all ubuntu nvidia-smi -L

# 3. devcontainer CLI (needs Node >= 18 on the host)
if ! command -v devcontainer >/dev/null; then
  if ! command -v node >/dev/null || [ "$(node -v | sed 's/^v//; s/\..*//')" -lt 18 ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
  sudo npm install -g @devcontainers/cli
fi

# 4. Optional idle stop: every 5 min, count idle checks (GPU < 5% and load < 1);
#    shut down after IDLE_MIN minutes of them. Disable with: sudo touch /var/tmp/no-idle-stop
if [ -n "$IDLE_MIN" ]; then
  sudo tee /usr/local/bin/idle-stop >/dev/null <<SCRIPT
#!/usr/bin/env bash
IDLE_MIN=$IDLE_MIN
STATE=/var/tmp/idle-count
SCRIPT
  sudo tee -a /usr/local/bin/idle-stop >/dev/null <<'SCRIPT'
[ -e /var/tmp/no-idle-stop ] && exit 0
gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | sort -n | tail -1)
load=$(cut -d' ' -f1 /proc/loadavg)
if [ "${gpu:-0}" -lt 5 ] && awk -v l="$load" 'BEGIN { exit !(l < 1.0) }'; then
  n=$(( $(cat "$STATE" 2>/dev/null || echo 0) + 1 ))
else
  n=0
fi
echo "$n" > "$STATE"
if [ $(( n * 5 )) -ge "$IDLE_MIN" ]; then
  rm -f "$STATE"
  shutdown -h now
fi
SCRIPT
  sudo chmod +x /usr/local/bin/idle-stop
  echo '*/5 * * * * root /usr/local/bin/idle-stop' | sudo tee /etc/cron.d/idle-stop >/dev/null
  echo "Idle stop: on, after $IDLE_MIN min (disable: sudo touch /var/tmp/no-idle-stop)"
fi

echo
echo "Server ready. For each project: put its secrets in ~/.config/claude-dev and inputs in"
echo "~/data/<repo> (see .devcontainer/README.md), then run .devcontainer/up.sh"
