# Claude Code dev container

A sandboxed container for working on a repo with Claude Code: prototype on a laptop (CPU), run
full size on a GPU server (CUDA). One image; `up.sh` picks CPU or CUDA builds for the env.

Placeholders below:
- `<repo>`: the name you give the project's repository, e.g. `coding_practice`. It is also the
  folder name, `~/repo/<repo>`, and the kit uses it for everything else.
- `<you>`: your GitHub user name.

## Getting started

### 1. Once per laptop
- Install Docker, Miniforge, Node >= 18 and, for step 2, the GitHub CLI `gh` (optional).
- `npm install -g @devcontainers/cli`
- Once ever: mark the `claude-devcontainer` repo as a template on GitHub (Settings > General >
  Template repository).

### 2. Create the project
From `~/repo` (or use "Use this template" on GitHub, then clone into `~/repo/<repo>`):
```bash
gh repo create <repo> --private --template <you>/claude-devcontainer --clone
cd <repo>
pkg=$(basename "$PWD" | tr - _)     # the Python package name: my-proj -> my_proj
git grep -l myproject -- ':!.devcontainer' | xargs sed -i "s/myproject/$pkg/g"
```
Keep the clone at `~/repo/<repo>`: the kit takes the project's name from the folder. The
package name differs from `<repo>` only if `<repo>` has hyphens; use underscores and they match.

**A throwaway project, with no GitHub repo:** clone the template locally and drop its origin,
then run the same `pkg=`, `sed` and `git mv` lines and commit:
```bash
git clone ~/repo/claude-devcontainer ~/repo/<repo> && cd ~/repo/<repo>
git remote remove origin
```
Skip the GitHub token in step 4 and the pushes. Claude's clone then has no origin, so on the
GPU server the `git fetch origin` in `claude/server.md` does not apply. To remove it later, see
[Removing a project](#removing-a-project).

### 3. Describe the project
Fill in `environment.yml` (packages), `.devcontainer-domains` (extra hosts the container may
reach), `CLAUDE.md` ("The project") and `README.md`. Commit and push. Leave `pytorch` unpinned
(not `pytorch-gpu` or `pytorch-cpu`): the machine picks the variant.

### 4. Secrets and data
For a private repo, make a GitHub token so Claude can fetch from it (read only): GitHub >
Settings > Developer settings > Fine-grained tokens > Generate, with repository access
"Only select repositories" = `<repo>` and permission Contents: Read-only. Save it:
```bash
mkdir -p ~/.config/claude-dev/repos/<repo>
cat > ~/.config/claude-dev/repos/<repo>/gh-token     # paste the token, Enter, Ctrl-D
chmod 600 ~/.config/claude-dev/repos/<repo>/gh-token
```
Optional, shared by all projects (`chmod 600` too): a Hugging Face read token in
`~/.config/claude-dev/shared/hf-token`, and for W&B a line
`machine api.wandb.ai login user password <key>` in `~/.config/claude-dev/shared/netrc`.
Input data goes in `~/data/<repo>/`, which the container sees read-only as `/data`.

### 5. A laptop env for your editor
LSP, formatters and debugging on the host use their own env, made from the same file and
named by its `name:` line (the package name):
```bash
conda env create -f environment.yml && conda activate <pkg>
pip install --no-deps --no-build-isolation -e .
```
After `environment.yml` changes: `conda env update -n <pkg> -f environment.yml --prune`
(`--prune` removes what the file no longer lists).

### 6. Start Claude
```bash
~/repo/<repo>/.devcontainer/up.sh      # builds or starts the container, opens bash in it
claude --dangerously-skip-permissions  # inside
```
The first start takes 15-30 min: the image build, then the conda env, which is built into a
volume once per agent and machine. A new project reuses the cached image layers, so only its
env build is slow. The first time, Claude prints a login URL: open it in your browser and paste
the code back.

### 7. Review and merge Claude's work
In your clone: `git fetch agent`, then read the diff before checking anything out (magit:
`d r` with `main..agent/main`). Look hardest at `environment.yml`, `.devcontainer-domains`,
`.devcontainer/`, `.dir-locals.el` and `conftest.py`: they change the next build, your host
env or what runs on your side. Then merge or check out, and push.

## Day to day
- `up.sh` again: another shell in the same container. Your work in it survives a restart;
  `up.sh --rebuild` (after a change to `.devcontainer/` or `.devcontainer-domains`) starts a
  fresh container from a new image. The conda env is in a volume and survives both.
- Commit kit changes in your clone, then `up.sh --rebuild`. On the server, push from the
  laptop and `git pull` first.
- Another host: add it to `.devcontainer-domains`. A new dependency: add it to
  `environment.yml` and run `conda env update -n dev -f environment.yml --prune` in the
  container (Claude may). A start does it anyway when the file changed since the last build.
- A broken or suspect env: `up.sh --reset-env` deletes the agent's env volume; the start
  rebuilds it (package downloads are cached).
- A kit fix made in one project does not reach the others or the template: copy it over.

### More than one agent
`up.sh agent-2` gives a second agent its own clone, container and remote `agent-2`, so two
agents can work on different jobs without touching each other's files. Agents of one repo
share its image, secrets, `/data`, Claude login, HF cache and conda package cache; each has
its own env. Keep their branches distinct.

### Removing a project
```bash
c=$(docker ps -aq --filter label=devcontainer.local_folder=$HOME/workspaces/<repo>/agent)
img=$(docker inspect -f '{{.Image}}' $c); docker rm -f $c; docker image rm $img
docker volume rm claude-dev-config-<repo> claude-dev-history-<repo> claude-dev-hf-<repo> \
  claude-dev-pkgs-<repo> claude-dev-env-<repo>-agent
rm -rf ~/workspaces/<repo> ~/repo/<repo> ~/data/<repo> ~/.config/claude-dev/repos/<repo>
```
Repeat the first two lines and the env volume for each extra agent (`.../<repo>/agent-2`,
`claude-dev-env-<repo>-agent-2`). Projects can share an image: `docker image rm` then refuses,
which is harmless.

## GPU server
Needs an NVIDIA driver and Docker with GPU access (NVIDIA Container Toolkit), e.g. an AWS Deep
Learning AMI. Once per machine, clone with the read-only token and set the machine up:
```bash
git clone --config credential.helper='!f() { test "$1" = get && echo username=x-access-token && echo password=$(cat $HOME/.config/claude-dev/repos/<repo>/gh-token); }; f' \
  https://github.com/<you>/<repo>.git ~/repo/<repo>
~/repo/<repo>/.devcontainer/server-setup.sh --idle-stop 60   # cloud: stop after 60 idle min
```
Copy the secrets to `~/.config/claude-dev/` and inputs to `~/data/<repo>/`. Every session:
```bash
git -C ~/repo/<repo> pull              # what you pushed from the laptop
~/repo/<repo>/.devcontainer/up.sh      # add --rebuild if the kit changed
```
Inside, run `tmux new -A -s main` first and start Claude (and your own experiments) in it, so
they survive an SSH drop. On a cloud instance, attach no IAM role: the firewall blocks the
metadata endpoint, but there should be nothing to find.

Getting Claude's commits back to the laptop (no write token anywhere):
```bash
git remote add ec2 <ssh-host>:workspaces/<repo>/agent   # once per agent; <ssh-host> from ~/.ssh/config
git fetch ec2
```

## How it works

### The model
- **Your clone**, `~/repo/<repo>`: you edit, review and push here. The image is built from
  it, so only reviewed files reach the image and the firewall config.
- **Claude's clone**, one per agent, `~/workspaces/<repo>/<name>` (default name `agent`): made
  by `up.sh` on its first run and mounted at `/workspace` in that agent's container. Its
  origin is GitHub over HTTPS with a read-only token; push is disabled.
- You get Claude's work by fetching it into your clone (remote `<name>`, or `ec2`).

**Treat Claude's clone as untrusted on the host.** Fetch from it, nothing else: no other git
command, magit, editor, LSP or tests there. Git, Emacs and pytest all run things a repo can
plant (config via `.git/commondir`, `.dir-locals.el`, `conftest.py`). Fetching runs
`upload-pack`, which git designs to be safe against an untrusted repo.

### What it gives you
- An egress firewall: GitHub, Anthropic, npm, conda-forge and PyPI, plus the hosts in
  `.devcontainer-domains` (each with its subdomains); no IPv6. DNS goes through a local
  resolver that answers only for those, so DNS cannot carry data out, and allowed addresses
  follow DNS, so CDNs that rotate IPs keep working.
- The project's conda env (always named `dev`), on PATH, in a volume per agent. At every
  start it is built from the agent's `environment.yml` if that changed since the last build
  (a hash in the volume), so dependency changes need no rebuild. This env follows the
  agent's file unreviewed: it only ever runs in the container, and the agent could install
  packages anyway. Your host env (step 5) comes from your reviewed file. The project is
  installed editable (`--no-deps`) at every start.
- CPU builds of conda packages on the laptop. On a host with an NVIDIA GPU, `up.sh` sets
  `CONDA_OVERRIDE_CUDA` in the container to the driver's CUDA version, giving CUDA builds
  plus GPU passthrough. At every start the container checks this matches the GPU it can see.
- Secrets mounted read-only: a GitHub token per repo, the HF token and W&B key shared.
- Per-machine instructions for Claude: `CLAUDE.local.md` in Claude's clone imports
  `claude/local.md` or `claude/server.md`.
- Persistent volumes for Claude's config (so its login), shell history, the HF cache and
  conda's package cache, one set per repo, shared by that repo's agents; and one per agent
  for its conda env.

What the firewall does not stop: allowed hosts accept anyone's credentials, so a
prompt-injected agent could upload to GitHub, Anthropic, Hugging Face or W&B with an
attacker's token. Don't put anything in the repo, `/data` or the secrets you could not live
with leaking. Services on the host's Docker bridge network are also reachable.

### Host layout
```
~/repo/<repo>/                               your clone
~/workspaces/<repo>/<name>/                  an agent's clone (made by up.sh)
~/data/<repo>/                               -> /data (read-only), inputs you put there
~/.config/claude-dev/shared/hf-token         HF read token (hf_...)
~/.config/claude-dev/shared/netrc            machine api.wandb.ai login user password <key>
~/.config/claude-dev/repos/<repo>/gh-token   fine-grained token: this repo only, Contents read-only
```
`up.sh` creates the directories; you add the files (`chmod 600`).
