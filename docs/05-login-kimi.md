[← back to README](../README.md)

# 5. Log in to Kimi Code (Moonshot)

**Cost: paid.** Subscription tiers only ($19–$199/mo), and new subscriptions have been sold out
since July 2026. Logging in proves who you are — it does **not** grant access. Without an active
plan the CLI will authenticate and then refuse to run.

Do Codex and Gemini first. Come back to this one last.

---

## Steps

```bash
kimi          # then type /login inside the TUI
```

Four options appear. `.ai` is the international service, `.com` is China mainland:

| Option | Use it when |
|---|---|
| Kimi Code (**kimi.ai/code**) | Default choice — subscription OAuth, international |
| Kimi Code (kimi.com/code) | You have a China-mainland Kimi account |
| Kimi Platform (API key · platform.kimi.ai) | Fallback if OAuth reports no active plan |
| Kimi Platform (API key · platform.kimi.com) | Same, China mainland |

Picking a **Kimi Code** option starts a device-code flow — it prints a URL and a code, it does
**not** ask you for a key. Then:

1. Open the URL in your **host** browser.
2. The page asks for a **phone number** and sends an SMS code. That is Kimi's ordinary account
   login. If it rejects your country's number, look for an email or Google option on that page.
3. The page then shows **Authorize device** — check the code matches your terminal, and approve.
4. The terminal continues on its own.

Picking a **Kimi Platform** option asks for an API key instead. Make it persistent:

```bash
echo 'MOONSHOT_API_KEY=paste-key-here' > ~/.kimi-code/.env
```

---

## If `/login` fails with `fetch failed`

```
Error: Login failed: OAuth request to
https://auth.kimi.ai/api/oauth/device_authorization failed: fetch failed
```

This is the firewall, and almost always a **stale allowlist** — `allowed-domains.txt` is baked
into the image at build time, so adding hosts to it does nothing until you rebuild.

Check what the running container actually has:

```bash
grep -i kimi /etc/agent-sandbox/allowed-domains.txt
```

**Empty** → the container predates the edit. Rebuild it:
**F1 → Dev Containers: Rebuild Container**.

**Lists the hosts, still failing** → the allowlist is current but the IPs are not. Re-resolve:

```bash
sudo /usr/local/bin/init-firewall.sh
```

Either way you can unblock immediately without a rebuild:

```bash
EXTRA_ALLOWED_DOMAINS="auth.kimi.ai api.kimi.ai code.kimi.ai www.kimi.ai" \
  sudo /usr/local/bin/init-firewall.sh
```

That lasts until the container restarts. See [Network allowlist](06-network-allowlist.md).

Confirm the host is reachable before blaming the CLI:

```bash
curl -sS --connect-timeout 8 -o /dev/null -w '%{http_code}\n' \
  https://auth.kimi.ai/api/oauth/device_authorization
```

A number means it is reachable and the fault is inside the CLI. A failure means it is still
blocked.

---

## Where the credentials live

`/home/node/.kimi-code`, mounted from the named volume `agent-kimi-config`.

---

Next: **[Network allowlist](06-network-allowlist.md)**
