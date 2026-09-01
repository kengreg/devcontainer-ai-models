#!/usr/bin/env bash
#
# OPTIONAL CLI launcher for the AI agents sandbox.
#
# Not needed for the normal workflow - in VS Code, use
#   F1 -> "Dev Containers: Reopen in Container"
# and then just type claude / codex / gemini / kimi in the terminal.
#
# This script is for working without VS Code (CI, a plain terminal, scripting).
# It needs: npm install -g @devcontainers/cli
#
#   agent.sh up             build + start + raise firewall
#   agent.sh claude         run Claude Code inside the sandbox
#   agent.sh codex          run Codex inside the sandbox
#   agent.sh gemini         run Gemini CLI
#   agent.sh kimi           run Kimi Code
#   agent.sh shell          plain zsh inside the sandbox
#   agent.sh login claude   browser OAuth login (paste the code back)
#   agent.sh seed gemini    copy host Google creds in
#   agent.sh firewall       re-apply the allowlist
#   agent.sh check          run the isolation self-checks
#   agent.sh status         is it running?
#   agent.sh rebuild        rebuild the image from scratch
#   agent.sh down           stop and remove the container
#   agent.sh reset-logins   wipe all stored agent credentials
#
# Run this from the HOST, not from inside a container. The folder can live
# anywhere; the workspace root is always the folder directly above it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/devcontainer.json"

c_red()  { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_dim()  { printf '\033[2m%s\033[0m\n' "$*"; }
die()    { c_red "error: $*" >&2; exit 1; }

# The workspace root is the PARENT of this folder, so the whole devcontainer/
# directory can be copied anywhere without editing paths. Override it with
# AGENT_WORKSPACE_ROOT in the env file.
#
# ${localWorkspaceFolder} in devcontainer.json resolves to this. The root itself
# is never mounted - only the children listed in "mounts" - which is exactly
# what keeps .env.agents, and everything else alongside it, out of reach.
DEFAULT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The env file sits in the workspace root, one level above this folder, so it is
# outside the Docker build context AND outside every mount. It is sourced here
# on the host and reaches the container only as runtime environment - never as a
# build arg, which would bake it into an image layer.
ENV_FILE="${AGENT_ENV_FILE:-${DEFAULT_ROOT}/.env.agents}"
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

WORKSPACE_ROOT="${AGENT_WORKSPACE_ROOT:-$DEFAULT_ROOT}"
[ -d "$WORKSPACE_ROOT" ] || die "workspace root not found: ${WORKSPACE_ROOT}"

require_deps() {
    command -v docker >/dev/null 2>&1 || die "docker not found. Install Docker Desktop and make sure it is running."
    docker info >/dev/null 2>&1 || die "docker is installed but not running. Start Docker Desktop."
    command -v devcontainer >/dev/null 2>&1 || die "devcontainer CLI not found. Install it with:
    npm install -g @devcontainers/cli"
}

load_env() {
    if [ -f "$ENV_FILE" ]; then
        c_dim "env:       ${ENV_FILE}"
    else
        c_dim "env:       none (${ENV_FILE} not found - fine if you use OAuth only)"
    fi
    # Referenced by devcontainer.json via ${localEnv:...}; export empty defaults
    # so the CLI does not warn about unset variables.
    export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
    export GEMINI_API_KEY="${GEMINI_API_KEY:-}"
    export MOONSHOT_API_KEY="${MOONSHOT_API_KEY:-}"
    export TZ="${TZ:-America/Los_Angeles}"
}

container_id() {
    # Located by its workspace volume rather than by a path label. The
    # devcontainer.config_file / local_folder labels hold a host path, and VS Code
    # on Windows writes those with backslashes - which never matches the POSIX
    # path a script sees from WSL or Git Bash. The volume name is the same
    # string everywhere, so this works no matter who started the container.
    docker ps -q \
        --filter "volume=agent-workspace-root" \
        --filter "status=running" 2>/dev/null | head -n1
}

require_running() {
    local id
    id="$(container_id)"
    [ -n "$id" ] || die "sandbox is not running. Start it with: $0 up"
    echo "$id"
}

dc_exec() {
    devcontainer exec \
        --workspace-folder "$WORKSPACE_ROOT" \
        --config "$CONFIG" \
        "$@"
}

cmd_up() {
    require_deps
    load_env
    c_dim "workspace: ${WORKSPACE_ROOT}"
    c_dim "config:    ${CONFIG}"
    devcontainer up --workspace-folder "$WORKSPACE_ROOT" --config "$CONFIG" "$@"
    c_grn "sandbox is up and the firewall self-test passed."
    echo
    echo "Next:  $0 claude  |   $0 codex   |   $0 gemini   |   $0 kimi   |   $0 shell"
}

cmd_rebuild() {
    require_deps
    load_env
    devcontainer up \
        --workspace-folder "$WORKSPACE_ROOT" \
        --config "$CONFIG" \
        --remove-existing-container \
        --build-no-cache
    c_grn "rebuilt."
}

cmd_down() {
    local id
    id="$(container_id)"
    if [ -z "$id" ]; then
        c_dim "not running."
        return 0
    fi
    docker rm -f "$id" >/dev/null
    c_grn "sandbox stopped and removed."
    c_dim "credential volumes were kept - your logins survive. Use 'reset-logins' to wipe them."
}

cmd_status() {
    require_deps
    local id
    id="$(container_id)"
    if [ -z "$id" ]; then
        echo "sandbox: stopped"
        return 0
    fi
    echo "sandbox: running (${id})"
    echo
    echo "mounted folders:"
    dc_exec bash -lc 'ls -1 /workspace' 2>/dev/null || true
}

cmd_agent() {
    local agent="$1"; shift
    case "$agent" in
        claude|codex|gemini|kimi) ;;
        *) die "unknown agent: $agent" ;;
    esac
    require_running >/dev/null
    # Exec the binary directly rather than through `zsh -lc "$agent $*"`, so
    # arguments containing spaces survive and the TUI keeps its TTY.
    dc_exec "$agent" "$@"
}

cmd_login() {
    local agent="${1:-}"
    [ -n "$agent" ] || die "usage: $0 login <claude|codex|gemini|kimi>"
    require_running >/dev/null
    case "$agent" in
        claude)
            c_dim "Run /login inside Claude Code. It prints a URL - open it on the HOST,"
            c_dim "approve, then paste the authorization code back into the terminal."
            dc_exec claude
            ;;
        codex)
            c_dim "Device-code login. Approve the code in any browser."
            c_dim "If this errors about device code auth, enable it in your ChatGPT security settings first."
            dc_exec codex login --device-auth
            ;;
        kimi)
            c_dim "Run /login inside Kimi and follow the device-code prompt."
            dc_exec kimi
            ;;
        gemini)
            c_red "Gemini's OAuth uses a dynamic localhost callback and does not work inside a container."
            echo "Use one of:"
            echo "  1. $0 seed gemini     - log in on the HOST, then copy the credentials in (recommended)"
            echo "  2. put a free Google AI Studio key in ${ENV_FILE} as GEMINI_API_KEY, then: $0 up"
            exit 1
            ;;
        *) die "unknown agent: $agent" ;;
    esac
}

cmd_seed() {
    local agent="${1:-}"
    [ -n "$agent" ] || die "usage: $0 seed <claude|codex|gemini|kimi>"
    require_running >/dev/null
    "${SCRIPT_DIR}/seed-credentials.sh" "$agent"
}

cmd_firewall() {
    require_running >/dev/null
    c_dim "re-applying the allowlist from allowed-domains.txt (baked into the image at build time)"
    c_dim "note: edits to allowed-domains.txt need '$0 rebuild' to take effect"
    dc_exec sudo /usr/local/bin/init-firewall.sh
}

cmd_check() {
    require_running >/dev/null
    echo "=== isolation self-checks ==="
    dc_exec bash -lc '
        pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
        fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; RC=1; }
        RC=0

        curl -sS --connect-timeout 5 -o /dev/null https://example.com 2>/dev/null \
            && fail "egress open: reached example.com" \
            || pass "blocked host is unreachable"

        code=$(curl -sS --connect-timeout 10 -o /dev/null -w "%{http_code}" https://api.openai.com/v1/models 2>/dev/null || echo 000)
        [ "$code" != "000" ] \
            && pass "allowlisted host reachable (api.openai.com -> HTTP $code)" \
            || fail "allowlisted host unreachable"

        code=$(curl -sS --connect-timeout 10 -o /dev/null -w "%{http_code}" https://api.anthropic.com/v1/models 2>/dev/null || echo 000)
        [ "$code" != "000" ] \
            && pass "allowlisted host reachable (api.anthropic.com -> HTTP $code)" \
            || fail "allowlisted host unreachable (api.anthropic.com)"

        curl -6 -sS --connect-timeout 5 -o /dev/null https://ipv6.google.com 2>/dev/null \
            && fail "IPv6 egress is open" \
            || pass "IPv6 is closed"

        sudo -n iptables -F 2>/dev/null \
            && fail "the sandbox user can flush its own firewall" \
            || pass "sandbox user cannot flush the firewall"

        echo "  ---- what the agents can see ----"
        ls -1 /workspace | sed "s/^/        /"
        echo "  ---- sudo rights ----"
        sudo -n -l 2>/dev/null | grep NOPASSWD | sed "s/^/    /" || echo "        (none)"
        exit $RC
    '
}

cmd_reset_logins() {
    read -r -p "Delete all stored agent logins (claude, codex, gemini, kimi)? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted."; return 0; }
    cmd_down || true
    docker volume rm -f agent-claude-config agent-codex-config agent-gemini-config agent-kimi-config >/dev/null 2>&1 || true
    c_grn "logins wiped. Run '$0 up' and log in again."
}

# Print the comment header at the top of this file, stopping at the first line
# of actual code.
usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"; }

case "${1:-}" in
    up)            shift; cmd_up "$@" ;;
    rebuild)       cmd_rebuild ;;
    down)          cmd_down ;;
    status)        cmd_status ;;
    shell)         require_running >/dev/null; dc_exec zsh ;;
    claude|codex|gemini|kimi) agent="$1"; shift; cmd_agent "$agent" "$@" ;;
    login)         shift; cmd_login "$@" ;;
    seed)          shift; cmd_seed "$@" ;;
    firewall)      cmd_firewall ;;
    check)         cmd_check ;;
    reset-logins)  cmd_reset_logins ;;
    ""|-h|--help|help) usage ;;
    *)             die "unknown command: $1 (try: $0 --help)" ;;
esac
