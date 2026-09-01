#!/usr/bin/env bash
#
# Copy an agent's credentials from the HOST into the sandbox's credential volume.
#
# Why this exists: Gemini CLI's OAuth flow binds a dynamic localhost callback
# port and does not complete inside a container (google-gemini/gemini-cli#2515,
# #1894, #27300). The workaround is to log in once on the host and move the
# resulting token in. Codex and Kimi support device-code login and do not need
# this, but the same path works for them if you prefer.
#
# Usage:  ./seed-credentials.sh <claude|codex|gemini|kimi>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="${1:-}"

die() { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[ -n "$AGENT" ] || die "usage: $0 <claude|codex|gemini|kimi>"

case "$AGENT" in
    # Claude Code's own OAuth works fine in a container (it prints a URL and
    # takes a pasted code back), so seeding is only a convenience here. On Linux
    # and macOS the token lives in .credentials.json next to .claude.json.
    claude) HOST_SUBDIR=".claude";    TARGET="/home/node/.claude";    FILES=(.credentials.json settings.json) ;;
    codex)  HOST_SUBDIR=".codex";     TARGET="/home/node/.codex";     FILES=(auth.json) ;;
    gemini) HOST_SUBDIR=".gemini";    TARGET="/home/node/.gemini";    FILES=(oauth_creds.json google_accounts.json installation_id) ;;
    kimi)   HOST_SUBDIR=".kimi-code"; TARGET="/home/node/.kimi-code"; FILES=(config.toml auth.json credentials.json) ;;
    *)      die "unknown agent: $AGENT" ;;
esac

# Find the host config dir. On Windows the CLI may have been run from PowerShell,
# in which case the credentials sit under the Windows profile, not the WSL one.
CANDIDATES=(
    "${HOME}/${HOST_SUBDIR}"
    "/mnt/c/Users/${USER:-}/${HOST_SUBDIR}"
    "/mnt/c/Users/${USERNAME:-}/${HOST_SUBDIR}"
)
HOST_DIR=""
for c in "${CANDIDATES[@]}"; do
    [ -d "$c" ] || continue
    for f in "${FILES[@]}"; do
        if [ -f "${c}/${f}" ]; then HOST_DIR="$c"; break 2; fi
    done
done

if [ -z "$HOST_DIR" ]; then
    die "no ${AGENT} credentials found on this host.

Log in on the host first:
    ${AGENT}          # then complete the browser sign-in
Looked in:
$(printf '    %s\n' "${CANDIDATES[@]}")"
fi

# Found by its workspace volume, not by a path label: VS Code on Windows writes
# those labels with backslashes, which never match a POSIX path from WSL.
CID="$(docker ps -q --filter "volume=agent-workspace-root" --filter "status=running" | head -n1)"
[ -n "$CID" ] || die "sandbox is not running.
Start it from VS Code (F1 -> Dev Containers: Reopen in Container), or with:
    ${SCRIPT_DIR}/agent.sh up"

echo "copying ${AGENT} credentials from ${HOST_DIR}"
copied=0
for f in "${FILES[@]}"; do
    [ -f "${HOST_DIR}/${f}" ] || continue
    docker cp "${HOST_DIR}/${f}" "${CID}:${TARGET}/${f}"
    echo "  + ${f}"
    copied=$((copied + 1))
done

[ "$copied" -gt 0 ] || die "found the directory but none of the expected credential files: ${FILES[*]}"

# docker cp lands files as root; hand them back to the sandbox user.
docker exec -u root "$CID" chown -R node:node "$TARGET"
docker exec -u root "$CID" chmod -R go-rwx "$TARGET"

printf '\033[32m%s\033[0m\n' "done - ${copied} file(s) seeded into ${TARGET}"
echo "verify with:  ${SCRIPT_DIR}/agent.sh ${AGENT} --version"
