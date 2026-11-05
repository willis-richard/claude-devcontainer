# Dev container

You run inside a Docker container. It runs on my laptop (CPU build) and on a GPU server
(CUDA build); which one you are on is in CLAUDE.local.md.

## Network
- Egress firewall. Allowed: GitHub, Anthropic, npm, conda-forge, PyPI and the hosts in
  .devcontainer-domains, with their subdomains. Other names do not resolve. If a download
  fails, tell me the blocked host. Do not look for workarounds.

## Files
- /workspace is your own clone of the repo. Derived files (processed data, checkpoints,
  logs) go in outputs/, which is not committed.
- /data holds read-only inputs. Never write there; I fill it.
- Hugging Face downloads go to the default HF cache, a persistent volume. Ask me before
  downloading anything over 10 GB.
- Paths to data, models and outputs come from config, never hard-coded.

## Python
- Conda env `dev`, first on PATH (no activation needed). It lives in a persistent volume,
  built from environment.yml; each container start re-applies the file if it changed.
- Every dependency goes in environment.yml (conda-forge; pip only for packages not on
  conda-forge), none in pyproject.toml. After editing it, run
  `conda env update -n dev -f environment.yml --prune`.
- The project is installed editable at container start; never add `-e .` to environment.yml.

## The container itself
- The image is built from my clone, not yours: your edits to .devcontainer/ and
  .devcontainer-domains change nothing until I review and rebuild. Do not edit them; if they
  need a change, tell me what and why.

## Git and secrets
- Your commit identity is preset. You cannot push; I fetch your commits from this clone.
- Tokens are in /run/secrets. Never print, log or commit them.
