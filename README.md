# AI Agents Sandbox

A portable, isolated dev container for running **Claude Code (Anthropic)**, **Codex (OpenAI)**,
**Gemini CLI (Google)** and **Kimi Code (Moonshot)** against your projects. All four live in one
container; you pick which one by typing its command in the terminal.

Built from the two vendor reference implementations:
[`anthropics/claude-code/.devcontainer`](https://github.com/anthropics/claude-code/tree/main/.devcontainer)
and [`openai/codex/.devcontainer`](https://github.com/openai/codex/tree/main/.devcontainer)
(OpenAI's hardened `devcontainer.secure.json` profile).

---

## Setup guides

Do them in this order. Step 1 is required; pick whichever agents you want after that.

| # | Guide | What it covers |
|---|---|---|
| 1 | **[Set up in VS Code](docs/01-setup-vscode.md)** | Prerequisites, where the folder goes, choosing what the agents can see, first run |
| 2 | **[Log in to Codex](docs/02-login-codex.md)** | OpenAI / ChatGPT — **free**, start here |
| 3 | **[Log in to Gemini](docs/03-login-gemini.md)** | Google — **free**, but in-container OAuth is broken upstream |
| 4 | **[Log in to Claude](docs/04-login-claude.md)** | Anthropic — **paid**, but the login flow is the smoothest of the four |
| 5 | **[Log in to Kimi](docs/05-login-kimi.md)** | Moonshot — **paid plan required** |
| 6 | **[Network allowlist](docs/06-network-allowlist.md)** | When the firewall blocks something you need |
| 7 | **[Verify the isolation](docs/07-verifying.md)** | Prove each layer actually holds |

## What each one costs

| Agent | Cost |
|---|---|
| **Codex** | **Free.** Included in any ChatGPT plan, free tier included |
| **Gemini** | **Free.** Personal Google account = 1,000 req/day, 60/min. No credit card |
| **Claude Code** | **Paid.** Claude Pro/Max subscription, or pay-as-you-go API credits |
| **Kimi Code** | **Paid tiers only** ($19–$199/mo). New subscriptions sold out since July 2026 |

---

## What the isolation gives you

**Filesystem** — the agents see the container's own OS plus **exactly** the host folders listed
in `devcontainer.json` → `mounts`. Nothing else of your machine exists to them.

**Network** — outbound traffic is default-DROP with an IP allowlist rebuilt at every container
start. IPv6 is closed. DNS is pinned to the container's own resolvers.

**Privilege** — non-root user, no Docker socket, and a sudoers file listing exactly two scripts.
An agent **cannot flush the firewall that confines it**. (Many devcontainers ship
`NOPASSWD: ALL`, which makes the firewall decorative.)

### Web search still works

Asking Claude, Codex or Gemini to search the web is **not** a firewall leak. The query goes to
`api.anthropic.com` / `api.openai.com` / the Gemini API, the *provider's* servers run the search,
and the results come back over that same allowlisted connection. The container never reaches the
wider internet. The wall confines the container, not the model's knowledge.

---

## Files in this folder

| File | Purpose |
|---|---|
| `devcontainer.json` | Mounts, capabilities, lifecycle hooks. **The `mounts` list is the sandbox boundary.** |
| `Dockerfile` | The image: base tooling + the four agent CLIs |
| `allowed-domains.txt` | Outbound hostname allowlist. Baked into the image — edits need a rebuild |
| `init-firewall.sh` | Default-DROP egress firewall. Runs as root at every container start |
| `fix-perms.sh` | Hands the credential volumes to the sandbox user. Runs once, at create |
| `agent.sh` | Optional CLI launcher, for working without VS Code |
| `seed-credentials.sh` | Copies host OAuth credentials in (used by Gemini) |
| `.env.example` | Optional API-key fallbacks. Copy to `.env.agents` at the workspace root |

---

## Optional: the CLI launcher

`agent.sh` exists for working without VS Code — CI, a plain terminal, or scripting. It is not
needed for the IDE workflow. It requires `npm install -g @devcontainers/cli`.

```bash
./.devcontainer/agent.sh up            # build + start + raise firewall
./.devcontainer/agent.sh claude        # or codex / gemini / kimi / shell
./.devcontainer/agent.sh check         # run all isolation self-checks at once
./.devcontainer/agent.sh down
./.devcontainer/agent.sh --help
```

`check` is worth knowing even if you use VS Code — it runs the whole verification table in
[Verify the isolation](docs/07-verifying.md) in one command.

---

## Limits

Stated up front rather than discovered later. The first two are documented by OpenAI for their
own secure profile.

- **DNS exfiltration is still possible.** Pinning port 53 to the container's resolvers narrows
  the channel; it does not close it. Closing it needs a filtering resolver.
- **The allowlist is IP-based, not domain-based.** Shared CDN addresses mean allowlisting one
  host can incidentally allow its neighbours.
- **The host network is allowed** (`ALLOW_HOST_NETWORK=1`) so you can reach your own dev servers.
  This is the one place agents can touch something outside the mounted folders — they can reach
  other services listening on your host or LAN. This is *network* reach, not file access: they can
  talk to anything on a port (your dev server, an unprotected database), but cannot read your
  disk. Set it to `0` to close it.
- **Bind mounts are read-write** unless you add `,readonly`. The boundary controls *which* files
  are visible, not whether the agent can change them. Everything under a mounted folder is
  included — `.env`, `.git`, secrets.
- **Credentials are readable by the agent that uses them.** Unavoidable — a process that calls an
  API must hold its token. The goal here is confining reach, not hiding tokens from their user.
- **This confines the agent. It does not make an untrusted repository safe.**
