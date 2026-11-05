# Claude Code dev container: one Dockerfile for the laptop (CPU build) and the GPU server (CUDA build).
# The build context is the root of YOUR clone (up.sh passes --config from it), so the image only
# contains files you have reviewed. Dockerfile.dockerignore limits what the context passes.
FROM node:20

ARG TZ
ENV TZ="$TZ"

RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  tmux \
  locales \
  poppler-utils \
  dnsmasq-base \
  && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && locale-gen \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

RUN mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

ENV DEVCONTAINER=true

# Workspace and config directories. The HF cache dir exists here so its volume is owned by node.
RUN mkdir -p /workspace /home/node/.claude /home/node/.cache/huggingface && \
  chown -R node:node /workspace /home/node/.claude /home/node/.cache

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER node

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin
ENV SHELL=/bin/zsh
ENV EDITOR=vim
ENV VISUAL=vim

ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Miniforge + the project's env, always named `dev`, baked into the image.
# The env's bin is first on PATH, so `python` is the env's python without `conda activate`.
RUN curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-$(uname -m).sh" -o /tmp/mf.sh \
  && bash /tmp/mf.sh -b -p $HOME/miniforge3 && rm /tmp/mf.sh

# CPU or CUDA: the build cannot see a GPU, so conda-forge offers only CPU builds unless
# CONDA_OVERRIDE_CUDA is set. Build arg CUDA_VERSION sets it: empty (the laptop) = CPU builds;
# up.sh sets it on a GPU host to the driver's CUDA version, and the solver then prefers CUDA
# builds of unpinned packages such as `pytorch`.
# The cache mount keeps conda's package downloads between builds (outside the image), so a
# change to environment.yml only downloads what is new.
ARG CUDA_VERSION=""
COPY --chown=node:node environment.yml /tmp/environment.yml
RUN --mount=type=cache,target=/home/node/miniforge3/pkgs,uid=1000,gid=1000 \
  CONDA_OVERRIDE_CUDA="${CUDA_VERSION}" \
  $HOME/miniforge3/bin/conda env create -n dev -f /tmp/environment.yml \
  && rm /tmp/environment.yml
# A GPU build that still got CPU PyTorch fails here rather than in a full-size run.
RUN if [ -n "$CUDA_VERSION" ] && $HOME/miniforge3/bin/conda list -n dev --json \
      | jq -e '.[] | select(.name == "pytorch" and (.build_string | test("cpu")))' >/dev/null; then \
    echo "ERROR: CPU build of pytorch in a CUDA build; check environment.yml" >&2; exit 1; fi
# Which build this is, for the GPU check in post-start.sh. Empty = CPU.
ENV IMAGE_CUDA_VERSION=$CUDA_VERSION
ENV PATH=/home/node/miniforge3/envs/dev/bin:/home/node/miniforge3/bin:$PATH

# Claude Code after the env, so updating it does not rebuild the env. up.sh passes the current
# release as the version; a literal "latest" would be cached forever.
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Start scripts, firewall, project domains and shell config last: they change most often.
# The start script runs from here, never from Claude's clone.
USER root
COPY .devcontainer/init-firewall.sh .devcontainer/post-start.sh /usr/local/bin/
COPY .devcontainer-domains /etc/claude-dev/project-domains
RUN chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/post-start.sh && \
  chmod 0644 /etc/claude-dev/project-domains && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node

COPY --chown=node:node .devcontainer/shellrc /home/node/.shellrc
RUN echo 'source ~/.shellrc' >> ~/.zshrc && echo 'source ~/.shellrc' >> ~/.bashrc
