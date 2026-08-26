#!/bin/bash
#
# Default-DROP egress firewall for the AI agents sandbox.
#
# Derived from the two vendor reference implementations:
#   - anthropics/claude-code/.devcontainer/init-firewall.sh
#   - openai/codex/.devcontainer/init-firewall.sh
#
# Differences from those, all deliberate:
#   1. Domains are read from a file, not hardcoded here (like OpenAI's version).
#   2. DNS is pinned to the container's own resolvers instead of port 53 being
#      open to the world.
#   3. IPv6 is dropped entirely - otherwise it is a complete bypass of the v4
#      allowlist.
#   4. Outbound SSH is off by default (the Anthropic reference allows port 22 to
#      any host, which is both a tunnel and an exfiltration path).
#
# Run as root. The sandbox user is allowed to run exactly this script via sudo.
set -euo pipefail
IFS=$'\n\t'

ALLOWLIST_FILE="${ALLOWLIST_FILE:-/etc/agent-sandbox/allowed-domains.txt}"
INCLUDE_GITHUB_RANGES="${INCLUDE_GITHUB_RANGES:-1}"
ALLOW_HOST_NETWORK="${ALLOW_HOST_NETWORK:-1}"
ALLOW_SSH="${ALLOW_SSH:-0}"
PIN_DNS="${PIN_DNS:-1}"
# Extra hosts without editing the file, e.g. EXTRA_ALLOWED_DOMAINS="a.com b.com"
EXTRA_ALLOWED_DOMAINS="${EXTRA_ALLOWED_DOMAINS:-}"
# Self-test targets
VERIFY_BLOCKED_URL="${VERIFY_BLOCKED_URL:-https://example.com}"
VERIFY_ALLOWED_URL="${VERIFY_ALLOWED_URL:-https://api.openai.com/v1/models}"

log() { printf '  %s\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (use: sudo $0)" >&2
    exit 1
fi

echo "=== agent sandbox firewall ==="

# ---------------------------------------------------------------------------
# 1. Preserve Docker's internal DNS NAT rules before flushing, then restore
#    only those. Without this, name resolution inside the container dies.
# ---------------------------------------------------------------------------
DOCKER_DNS_RULES=$(iptables-save -t nat | grep '127\.0\.0\.11' || true)

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

if [ -n "$DOCKER_DNS_RULES" ]; then
    log "restoring Docker internal DNS rules"
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

# ---------------------------------------------------------------------------
# 2. Build the allowlist. This must happen while egress is still open, since it
#    needs DNS and an HTTPS call to the GitHub metadata endpoint.
# ---------------------------------------------------------------------------
ipset create allowed-domains hash:net

if [ ! -r "$ALLOWLIST_FILE" ]; then
    echo "ERROR: allowlist file not readable: $ALLOWLIST_FILE" >&2
    exit 1
fi

# Strip comments and blank lines.
mapfile -t DOMAINS < <(sed -e 's/#.*$//' -e 's/[[:space:]]//g' "$ALLOWLIST_FILE" | grep -v '^$' || true)

if [ -n "$EXTRA_ALLOWED_DOMAINS" ]; then
    # IFS is pinned to newline/tab above, so restore space-splitting just for
    # this list - it is documented as space-separated.
    _saved_ifs="$IFS"; IFS=$' \n\t'
    for extra in $EXTRA_ALLOWED_DOMAINS; do
        DOMAINS+=("$extra")
    done
    IFS="$_saved_ifs"
fi

if [ "${#DOMAINS[@]}" -eq 0 ] && [ "$INCLUDE_GITHUB_RANGES" != "1" ]; then
    echo "ERROR: allowlist is empty - refusing to start with no egress at all" >&2
    exit 1
fi

if [ "$INCLUDE_GITHUB_RANGES" = "1" ]; then
    echo "Fetching GitHub IP ranges..."
    gh_ranges=$(curl -s --connect-timeout 10 https://api.github.com/meta || true)
    if [ -z "$gh_ranges" ] || ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
        echo "ERROR: could not fetch usable GitHub IP ranges" >&2
        exit 1
    fi
    while read -r cidr; do
        [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || continue
        ipset add allowed-domains "$cidr" -exist
    done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)
    log "GitHub ranges added"
fi

echo "Resolving allowlisted hosts..."
resolved_any=0
for domain in "${DOMAINS[@]}"; do
    ips=$(dig +short +time=3 +tries=2 A "$domain" | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || true)
    if [ -z "$ips" ]; then
        # A host that fails to resolve is a warning, not a hard stop: one dead
        # entry should not lock you out of the whole container.
        log "WARN  $domain did not resolve - skipped"
        continue
    fi
    while read -r ip; do
        ipset add allowed-domains "$ip" -exist
    done <<< "$ips"
    resolved_any=1
    log "ok    $domain"
done

if [ "$resolved_any" -eq 0 ] && [ "$INCLUDE_GITHUB_RANGES" != "1" ]; then
    echo "ERROR: nothing in the allowlist resolved - check DNS" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. Accept rules. Order matters: these are appended before the policy flips to
#    DROP, and the catch-all REJECT goes last.
# ---------------------------------------------------------------------------
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

if [ "$PIN_DNS" = "1" ]; then
    NAMESERVERS=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || true)
    if [ -n "$NAMESERVERS" ]; then
        while read -r ns; do
            iptables -A OUTPUT -p udp -d "$ns" --dport 53 -j ACCEPT
            iptables -A OUTPUT -p tcp -d "$ns" --dport 53 -j ACCEPT
            log "DNS pinned to $ns"
        done <<< "$NAMESERVERS"
    else
        log "WARN  no usable nameserver found - allowing DNS to any host"
        iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
        iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
    fi
else
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
fi
iptables -A INPUT -p udp --sport 53 -j ACCEPT

if [ "$ALLOW_SSH" = "1" ]; then
    log "outbound SSH enabled"
    iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT  -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
fi

if [ "$ALLOW_HOST_NETWORK" = "1" ]; then
    HOST_IP=$(ip route | awk '/^default/ {print $3; exit}')
    if [ -z "$HOST_IP" ]; then
        echo "ERROR: failed to detect host IP from default route" >&2
        exit 1
    fi
    HOST_NETWORK=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0\/24/')
    log "host network allowed: $HOST_NETWORK (so you can reach your own dev servers)"
    iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# ---------------------------------------------------------------------------
# 4. Flip to default DROP and reject the remainder. REJECT rather than DROP so
#    a blocked agent fails fast with a clear error instead of hanging.
# ---------------------------------------------------------------------------
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# IPv6: no allowlist is maintained for it, so close it completely.
if command -v ip6tables >/dev/null 2>&1; then
    if ip6tables -L >/dev/null 2>&1; then
        ip6tables -F 2>/dev/null || true
        ip6tables -A INPUT  -i lo -j ACCEPT
        ip6tables -A OUTPUT -o lo -j ACCEPT
        ip6tables -P INPUT DROP
        ip6tables -P FORWARD DROP
        ip6tables -P OUTPUT DROP
        log "IPv6 dropped"
    else
        log "IPv6 unavailable in this kernel - nothing to close"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Self-test. devcontainer.json sets waitFor=postStartCommand, so a non-zero
#    exit here means you never get handed a shell in an unconfined container.
# ---------------------------------------------------------------------------
echo "Verifying..."

if curl --connect-timeout 5 -sS -o /dev/null "$VERIFY_BLOCKED_URL" 2>/dev/null; then
    echo "FAIL: reached $VERIFY_BLOCKED_URL - egress is NOT confined" >&2
    exit 1
fi
log "PASS  blocked  $VERIFY_BLOCKED_URL is unreachable"

if ! curl --connect-timeout 10 -sS -o /dev/null "$VERIFY_ALLOWED_URL" 2>/dev/null; then
    echo "FAIL: cannot reach $VERIFY_ALLOWED_URL - the allowlist is not working" >&2
    exit 1
fi
log "PASS  allowed  $VERIFY_ALLOWED_URL is reachable"

echo "=== firewall active ($(ipset list allowed-domains | grep -c '^[0-9]' || echo 0) entries) ==="
