#!/bin/bash
#
# Named volumes are created root-owned by Docker, so the sandbox user cannot
# write its own config until we hand them over. Runs once, from postCreateCommand.
#
# This is the only other thing the sandbox user may run as root, and it is
# deliberately narrow: it touches nothing but the agent config dirs.
set -euo pipefail

USERNAME="${SANDBOX_USER:-node}"

for dir in \
    "/home/${USERNAME}/.codex" \
    "/home/${USERNAME}/.gemini" \
    "/home/${USERNAME}/.kimi-code" \
    "/home/${USERNAME}/.cache" \
    /commandhistory
do
    [ -d "$dir" ] || continue
    chown -R "${USERNAME}:${USERNAME}" "$dir"
    chmod 0700 "$dir"
done

echo "agent config directories ready"
