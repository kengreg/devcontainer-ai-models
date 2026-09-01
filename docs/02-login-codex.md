[← back to README](../README.md)

# 2. Log in to Codex (OpenAI)

**Cost: free.** Included in any ChatGPT plan, free tier included. Nothing extra to buy.

Start with this one. It is the easiest to get working, and its hosts are proven reachable on
every boot — the firewall self-test calls `api.openai.com`.

---

## Steps

Run these in the VS Code terminal, **inside the container**.

```bash
codex login --device-auth
```

It offers three options. Pick **device code**.

> Do **not** pick "Sign in with ChatGPT" — that opens a localhost browser callback, which does not
> work inside a container. Do not pick "own API key" either; that is the paid path.

Then:

1. Copy the URL and the code it prints.
2. Open the URL in your **host** browser — not in the container.
3. Enter the code and approve.
4. The terminal picks it up automatically.

Start it:

```bash
codex
```

Ask it to read a file under `/workspace` to confirm it can see your project.

---

## If it fails

**"device code auth is not enabled" / a workspace-admin error**
Enable device-code auth in your ChatGPT security settings, then retry.

**`fetch failed` naming a host**
The firewall is blocking it — see [Network allowlist](06-network-allowlist.md).

---

## Where the credentials live

`/home/node/.codex`, mounted from the named volume `agent-codex-config`. They survive rebuilds
and never land in your project folders or in an image layer.

Wipe them with `./.devcontainer/agent.sh reset-logins`.

---

## Web search is not a firewall leak

Codex can search the web even though the container cannot reach `example.com`. The query goes to
`api.openai.com` (allowlisted), OpenAI's servers run the search, and the results come back over
that same connection. Nothing leaves the allowlist.

---

Next: **[Log in to Gemini](03-login-gemini.md)**
