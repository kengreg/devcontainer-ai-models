# AI agents sandbox image: Claude Code (Anthropic), Codex (OpenAI),
# Gemini CLI (Google), Kimi Code (Moonshot).
#
# Node 22 is the baseline because Kimi Code requires >= 22.19; Claude, Codex and
# Gemini are all fine on it (Claude Code itself wants >= 18).
FROM node:22-bookworm-slim

ARG TZ
ENV TZ="$TZ"

ARG USERNAME=node

# ---------------------------------------------------------------------------
# Base tooling.
# iptables / ipset / iproute2 / dnsutils / aggregate / jq are what
# init-firewall.sh needs. The rest is ordinary dev ergonomics.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg2 \
    less \
    procps \
    psmisc \
    sudo \
    zsh \
    fzf \
    man-db \
    unzip \
    jq \
    nano \
    vim \
    ripgrep \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    python3 \
    python3-venv \
  && update-ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# GitHub CLI is not in Debian bookworm main, so pull it from the official repo.
RUN mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO /etc/apt/keyrings/githubcli-archive-keyring.gpg \
       https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# git-delta, for readable diffs
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) \
  && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
  && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

ENV DEVCONTAINER=true \
    AGENT_SANDBOX=true

# Workspace, shell history, and one config dir per agent. Each config dir is a
# mount point for a named volume (see devcontainer.json) so OAuth tokens survive
# rebuilds without ever landing in the repo or in an image layer.
RUN mkdir -p /workspace \
             /commandhistory \
             /home/${USERNAME}/.claude \
             /home/${USERNAME}/.codex \
             /home/${USERNAME}/.gemini \
             /home/${USERNAME}/.kimi-code \
             /home/${USERNAME}/.cache \
             /usr/local/share/npm-global \
  && touch /commandhistory/.bash_history \
  && chown -R ${USERNAME}:${USERNAME} \
       /workspace /commandhistory /usr/local/share/npm-global /home/${USERNAME}

WORKDIR /workspace

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/home/${USERNAME}/.local/bin
ENV SHELL=/bin/zsh \
    EDITOR=nano \
    VISUAL=nano

# Tell each CLI where its config lives, so the volume mounts above are the
# single place credentials are kept.
ENV CODEX_HOME=/home/${USERNAME}/.codex \
    KIMI_CODE_HOME=/home/${USERNAME}/.kimi-code \
    CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude

USER ${USERNAME}

ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export HISTFILE=/commandhistory/.bash_history" \
  -x

# ---------------------------------------------------------------------------
# Agent CLIs. Each is opt-out via a build arg so the image only carries what you
# actually use. Versions default to "latest"; pin them for a reproducible image.
# ---------------------------------------------------------------------------
ARG INSTALL_CLAUDE=true
ARG INSTALL_CODEX=true
ARG INSTALL_GEMINI=true
ARG INSTALL_KIMI=true

ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest
ARG GEMINI_VERSION=latest
ARG KIMI_VERSION=latest

RUN set -eux; \
    if [ "$INSTALL_CLAUDE" = "true" ]; then npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"; fi; \
    if [ "$INSTALL_CODEX"  = "true" ]; then npm install -g "@openai/codex@${CODEX_VERSION}"; fi; \
    if [ "$INSTALL_GEMINI" = "true" ]; then npm install -g "@google/gemini-cli@${GEMINI_VERSION}"; fi; \
    if [ "$INSTALL_KIMI"   = "true" ]; then npm install -g "@moonshot-ai/kimi-code@${KIMI_VERSION}"; fi; \
    npm cache clean --force

# ---------------------------------------------------------------------------
# Confinement.
#
# The scripts are root-owned and the sudoers entry lists exactly two of them.
# This is what makes the firewall hold: an agent can re-run init-firewall.sh
# (harmless) but cannot run `iptables -F` on itself. A broad `NOPASSWD: ALL`,
# which many devcontainers ship, would make the whole firewall decorative.
# ---------------------------------------------------------------------------
USER root

COPY init-firewall.sh fix-perms.sh /usr/local/bin/
COPY allowed-domains.txt /etc/agent-sandbox/allowed-domains.txt

RUN chown root:root /usr/local/bin/init-firewall.sh /usr/local/bin/fix-perms.sh \
                    /etc/agent-sandbox/allowed-domains.txt \
  && chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/fix-perms.sh \
  && chmod 0644 /etc/agent-sandbox/allowed-domains.txt \
  && printf '%s\n' \
       "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
       "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/fix-perms.sh" \
       > /etc/sudoers.d/agent-sandbox \
  && chmod 0440 /etc/sudoers.d/agent-sandbox \
  && visudo -c -f /etc/sudoers.d/agent-sandbox

USER ${USERNAME}
