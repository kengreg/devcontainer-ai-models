[← back to README](../README.md)

# 4. Log in to Claude Code (Anthropic)

**Cost: paid.** Either a Claude Pro / Max subscription, or pay-as-you-go API credits. There is no
free tier. Everything else about it is the easiest of the four: the OAuth flow is designed for
headless machines, so it works inside the container with no host seeding and no device-code
detour.

---

## Steps

Run this in the VS Code terminal, **inside the container**:

```bash
claude
```

On first run it walks you through theme, then login. If you are already past that screen, type:

```
/login
```

Two options appear:

| Option | Use it when |
|---|---|
| **Claude account with subscription** | You have Claude Pro or Max — flat monthly rate |
| **Anthropic Console account** | You bill per token against API credits |

Either way:

1. It prints a URL. Open it in your **host** browser — not in the container.
2. Approve the request.
3. The page gives you an **authorization code**. Copy it, paste it back into the terminal.

That paste-the-code step is why this works in a sandbox at all: Claude Code never needs to bind a
localhost callback port, which is exactly what breaks [Gemini](03-login-gemini.md) in here.

Confirm it can see your project:

```bash
claude
> read /workspace/backend and tell me what this project is
```

---

## API key instead of a login

If you would rather bill per token and skip the interactive flow, put the key in the env file at
the workspace root (`.env.agents`, one level above `.devcontainer/`):

```bash
ANTHROPIC_API_KEY=sk-ant-...
```

Then `agent.sh up` — or, in VS Code, set it in your own environment before launching, since
`${localEnv:...}` resolves against VS Code's environment and not against that file. It reaches the
container as runtime environment only, never as a build arg.

Do not do both. A key in the environment takes precedence over a subscription login and will bill
you per token without saying so.

---

## If it fails

**The login URL will not open / connection errors**
The firewall is blocking a host. Claude Code needs `api.anthropic.com`, `claude.ai` and
`console.anthropic.com`; the first is verified on every boot. Check the running container's
allowlist:

```bash
grep -iE 'anthropic|claude' /etc/agent-sandbox/allowed-domains.txt
```

**Empty** → the container predates this edit. `allowed-domains.txt` is baked into the image at
build time, so rebuild: **F1 → Dev Containers: Rebuild Container**.

**Listed, still failing** → the IPs rotated. Re-resolve:

```bash
sudo /usr/local/bin/init-firewall.sh
```

Or unblock immediately, without a rebuild:

```bash
EXTRA_ALLOWED_DOMAINS="api.anthropic.com claude.ai console.anthropic.com" \
  sudo /usr/local/bin/init-firewall.sh
```

See [Network allowlist](06-network-allowlist.md).

**"Invalid API key" right after a successful `/login`**
`ANTHROPIC_API_KEY` is set in the environment and is overriding the subscription token. Unset it,
or clear it from `.env.agents`.

---

## Where the credentials live

`/home/node/.claude`, mounted from the named volume `agent-claude-config` and pointed at by
`CLAUDE_CONFIG_DIR`. Settings, history and the OAuth token all sit there, so they survive rebuilds
and never land in your project folders or in an image layer.

Wipe them with `./.devcontainer/agent.sh reset-logins`.

To copy an existing host login in instead of logging in again:

```bash
./.devcontainer/agent.sh seed claude
```

---

## Permission prompts still apply

Claude Code asks before edits and commands as usual. The sandbox is the outer wall, not a
replacement for that. If you want it to stop asking *within* these walls, `--dangerously-skip-permissions`
is the intended use case for a confined container like this one — the firewall and the mount list
are what make that a defensible trade rather than a reckless one.

---

Next: **[Log in to Kimi](05-login-kimi.md)**
