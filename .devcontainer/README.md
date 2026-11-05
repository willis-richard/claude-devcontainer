# Claude Code dev container

A sandboxed container for working on this repo with Claude Code: prototype on a laptop
(CPU), run full size on a GPU server (CUDA). One Dockerfile; `up.sh` picks the build.

## The model
- **Your clone**, `~/repo/<repo>`: you edit, review and push here. The image is built from
  it, so only reviewed files reach the image and the firewall config.
- **Claude's clone**, `~/workspaces/<repo>`: made by `up.sh` on its first run and mounted at
  `/workspace`. Its origin is GitHub over HTTPS with a read-only token; push is disabled.
- You get Claude's work by fetching it into your clone (remote `agent`, or `ec2`).

**Treat Claude's clone as untrusted on the host.** Fetch from it, nothing else: no other git
command, magit, editor, LSP or tests there. Git, Emacs and pytest all run things a repo can
plant (config via `.git/commondir`, `.dir-locals.el`, `conftest.py`). Fetching runs
`upload-pack`, which git designs to be safe against an untrusted repo.

## What it gives you
- An egress firewall: GitHub, Anthropic, npm, conda-forge and PyPI, plus the hosts in
  `.devcontainer-domains` (each with its subdomains); no IPv6. DNS goes through a local
  resolver that answers only for those, so DNS cannot carry data out, and allowed addresses
  follow DNS, so CDNs that rotate IPs keep working.
- The project's conda env (always named `dev`), built from `environment.yml` into the image
  and on PATH. The project is installed editable (`--no-deps`) at every start.
- CPU builds of conda packages on the laptop. On a host with an NVIDIA GPU, `up.sh` sets the
  build arg `CUDA_VERSION` to the driver's CUDA version, giving CUDA builds plus GPU
  passthrough. At every start the container checks its build matches the GPU it can see.
- Secrets mounted read-only: a GitHub token per repo, the HF token and W&B key shared.
- Per-machine instructions for Claude: `CLAUDE.local.md` in Claude's clone imports
  `claude/local.md` or `claude/server.md`.
- Persistent volumes for Claude's config, shell history and the HF cache.

What the firewall does not stop: allowed hosts accept anyone's credentials, so a
prompt-injected agent could upload to GitHub, Anthropic, Hugging Face or W&B with an
attacker's token. Don't put anything in the repo, `/data` or the secrets you could not live
with leaking. Services on the host's Docker bridge network are also reachable.

## Host layout
```
~/repo/<repo>/                               your clone
~/workspaces/<repo>/                         Claude's clone (made by up.sh)
~/data/<repo>/                               -> /data (read-only), inputs you put there
~/.config/claude-dev/shared/hf-token         HF read token (hf_...)
~/.config/claude-dev/shared/netrc            machine api.wandb.ai login user password <key>
~/.config/claude-dev/repos/<repo>/gh-token   fine-grained token: this repo only, Contents read-only
```
`up.sh` creates the directories; you add the files (`chmod 600`). Skip `gh-token` for a
public repo.

## Start a project from this template
Create the repo from the template on GitHub, clone it to `~/repo/<repo>`, then rename the
package (the kit itself never mentions it):
```bash
git grep -l myproject -- ':!.devcontainer' | xargs sed -i 's/myproject/<name>/g'
git mv src/myproject src/<name>
```
Edit `environment.yml`, `.devcontainer-domains`, `CLAUDE.md` and `README.md`, and commit.
Leave `pytorch` unpinned (not `pytorch-gpu` or `pytorch-cpu`): the build arg picks the
variant, and a CUDA build that still gets CPU PyTorch fails at build time.

## Laptop
Once: `npm install -g @devcontainers/cli`, and a host env for LSP, formatters and debugging,
made from the same file (it never clashes with the container's `dev` env):
```bash
conda env create -f environment.yml && conda activate <name>
pip install --no-deps --no-build-isolation -e .
```
Every session:
```bash
~/repo/<repo>/.devcontainer/up.sh      # builds or starts the container, attaches tmux
claude --dangerously-skip-permissions  # inside
```
The first build takes 15-30 min (mostly the conda env).

## Review
In your clone: `git fetch agent`, then read the diff before checking anything out (magit:
`d r` with `main..agent/<branch>`). Look hardest at `environment.yml`,
`.devcontainer-domains`, `.devcontainer/`, `.dir-locals.el` and `conftest.py`: they change
the next build or run on your side. Then merge or check out, and push.

## GPU server
Once per machine, clone with the read-only token and set the machine up:
```bash
git clone --config credential.helper='!f() { test "$1" = get && echo username=x-access-token && echo password=$(cat $HOME/.config/claude-dev/repos/<repo>/gh-token); }; f' \
  https://github.com/<you>/<repo>.git ~/repo/<repo>
~/repo/<repo>/.devcontainer/server-setup.sh --idle-stop 60   # cloud: stop after 60 idle min
```
Copy the secrets to `~/.config/claude-dev/` and inputs to `~/data/<repo>/`. Every session:
```bash
git -C ~/repo/<repo> pull              # what you pushed from the laptop
~/repo/<repo>/.devcontainer/up.sh      # add --rebuild if the kit or env changed
```
Run experiments in tmux yourself, or start Claude there. On a cloud instance, attach no IAM
role: the firewall blocks the metadata endpoint, but there should be nothing to find.

Getting Claude's commits back to the laptop (no write token anywhere):
```bash
git remote add ec2 <ssh-host>:workspaces/<repo>     # once; <ssh-host> from ~/.ssh/config
git fetch ec2
```

## Changing things
Commit the change in your clone, then `up.sh --rebuild`. On the server, push from the laptop
and `git pull` first.
- Another host: add it to `.devcontainer-domains`.
- New dependency: edit `environment.yml`. Claude can `conda env update -n dev -f
  environment.yml` in the running container meanwhile; the build caches conda downloads, so
  rebuilds only fetch what is new.
- A kit fix made here does not reach other projects made from the template: copy it over.
