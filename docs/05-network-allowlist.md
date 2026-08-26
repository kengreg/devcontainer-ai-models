[← back to README](../README.md)

# 5. Network allowlist — when the firewall blocks something

This is the normal loop for a default-deny firewall: a service reveals its hosts only when it
first calls them. Expect a couple of rounds the first time you log in to a new agent.

**Symptom** — a connection error naming a host, e.g.
`OAuth request to https://auth.example.ai/... failed: fetch failed`. The hostname in the error
*is* the thing to add.

---

## Unblock now (no rebuild)

In the container terminal — quit the agent first, or use a second terminal. Space-separated, as
many hosts as you like:

```bash
EXTRA_ALLOWED_DOMAINS="auth.example.ai api.example.ai" \
  sudo /usr/local/bin/init-firewall.sh
```

Wait for the two `PASS` lines. **This lasts until the container restarts.**

---

## Make it permanent

Add the hostnames to `allowed-domains.txt`, one per line, then rebuild:

> **F1** → `Dev Containers: Rebuild Container`

The file is `COPY`'d into the image at `/etc/agent-sandbox/allowed-domains.txt` at build time.
**Editing it and restarting does nothing** — the running container keeps the copy it was built
with. This is deliberate: your project folders are mounted read-write, so a live-mounted allowlist
would let an agent widen its own egress and then re-run `init-firewall.sh`.

Check what the running container actually has:

```bash
grep -i THE-HOST /etc/agent-sandbox/allowed-domains.txt
```

If that comes back empty, your container predates the edit. That is the single most common cause
of "I allowlisted it and it still fails".

---

## If a host that used to work starts failing

Its IPs rotated — the allowlist resolves names to IP addresses at apply time. Re-resolve:

```bash
sudo /usr/local/bin/init-firewall.sh
```

---

## Telling the two cases apart

```bash
curl -sS --connect-timeout 5 -o /dev/null -w '%{http_code}\n' https://THE-HOST/
```

- A **status code** → the host is reachable; the fault lies in the client, not the firewall.
- A **failure** → still blocked.

Some services sit behind a CDN whose IPs rotate between the moment the firewall resolves a name
and the moment the client connects. Hostname allowlisting cannot hold against that — see
Limits in the [README](../README.md).

---

## Knobs

All read by `init-firewall.sh` as environment variables:

| Variable | Default | Effect |
|---|---|---|
| `EXTRA_ALLOWED_DOMAINS` | *empty* | Extra hosts, space-separated, without editing the file |
| `INCLUDE_GITHUB_RANGES` | `1` | Pull GitHub's official CIDR ranges from `api.github.com/meta` |
| `ALLOW_HOST_NETWORK` | `1` | Reach your own machine and LAN — see below |
| `ALLOW_SSH` | `0` | Outbound port 22. Off by default: it is a tunnel and an exfil path |
| `PIN_DNS` | `1` | Restrict port 53 to the container's own resolvers |

### `ALLOW_HOST_NETWORK` — what it actually opens

Not the internet. Internet egress stays locked to the allowlist. This opens your **PC and your
local network** (the whole `/24`):

- your own dev servers — whatever you run on `:8000`, `:3000`, etc.
- your local database — Postgres / MySQL / Redis
- anything else on your wifi — router admin, NAS, printers, other machines

It is **network reach, not file access**. Agents can talk to anything listening on a port; they
cannot read your disk. The practical risk is an unprotected service, e.g. a database with no
password. Set it to `0` if you do not need to reach your dev server.

---

Next: **[Verify the isolation](06-verifying.md)**
