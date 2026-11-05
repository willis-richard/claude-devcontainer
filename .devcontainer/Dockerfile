# Claude Code dev container: one image for the laptop and the GPU server. The project's conda
# env is not in it: post-start.sh builds it into a volume (CPU or CUDA builds, set by up.sh).
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
ENV SHELL=/bin/bash
ENV EDITOR=vim
ENV VISUAL=vim

# Miniforge only. The project's env, always named `dev`, lives in a volume on envs/, and
# conda's package cache in another on pkgs/; the dirs exist here so the volumes are owned by
# node. The env's bin is first on PATH, so `python` is the env's python without activation.
RUN curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-$(uname -m).sh" -o /tmp/mf.sh \
  && bash /tmp/mf.sh -b -p $HOME/miniforge3 && rm /tmp/mf.sh \
  && mkdir -p $HOME/miniforge3/envs $HOME/miniforge3/pkgs
ENV PATH=/home/node/miniforge3/envs/dev/bin:/home/node/miniforge3/bin:$PATH

# up.sh passes the current Claude Code release as the version; a literal "latest" would be
# cached forever.
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
# History on the persistent volume, written after every command; fzf's Ctrl-R.
RUN printf '%s\n' \
  'export HISTFILE=/commandhistory/.bash_history' \
  "PROMPT_COMMAND='history -a'" \
  'source /usr/share/doc/fzf/examples/key-bindings.bash' \
  'source ~/.shellrc' >> ~/.bashrc
