[← back to README](../README.md)

# 7. Verify the isolation

Run these in the container terminal — or all at once from the host with
`./.devcontainer/agent.sh check`.

| Check | Expected |
|---|---|
| `curl --connect-timeout 5 https://example.com` | fails |
| `curl -o /dev/null -w '%{http_code}' https://api.openai.com/v1/models` | `401` — reached it, unauthenticated |
| `curl -o /dev/null -w '%{http_code}' https://api.anthropic.com/v1/models` | `401` — reached it, unauthenticated |
| `curl -6 --connect-timeout 5 https://ipv6.google.com` | fails |
| `sudo iptables -F` | `sudo: a password is required` |
| `sudo -l` | lists only `init-firewall.sh` and `fix-perms.sh` |
| `ls /workspace` | only the folders you listed in `mounts` |
| `ls /mnt` | no host drives |

---

## Recommended first run

Prove one layer at a time so a failure is unambiguous.

**1. Container + firewall, no accounts at all.** Reopen in container, then run the table above.
Everything must behave as listed before you log in to anything.

**2. First agent.** [Codex](02-login-codex.md) — `codex login --device-auth`, then `codex`. Ask it
to read a file under `/workspace`.

**3. Then the rest.** [Gemini](03-login-gemini.md) via host seeding,
[Claude](04-login-claude.md) via `/login` and a pasted code, and
[Kimi](05-login-kimi.md) last since it is the one that needs a paid plan.

---

## What a passing run does *not* prove

- **Web search still works** through Claude, Codex and Gemini. That is not a leak — the provider's servers
  run the search and return results over the allowlisted API connection. The container itself
  still cannot reach `example.com`, which is exactly what the first row of the table shows.
- **The host network is reachable** by design (`ALLOW_HOST_NETWORK=1`). Services on your machine
  and LAN are in scope. See [Network allowlist](06-network-allowlist.md).
- **Mounted folders are writable.** The boundary controls which files exist, not whether the agent
  changes them.

Full list in the [README](../README.md) → Limits.
