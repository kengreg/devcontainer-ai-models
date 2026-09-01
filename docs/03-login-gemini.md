[← back to README](../README.md)

# 3. Log in to Gemini (Google)

**Cost: free.** A personal Google account gives 1,000 requests/day on Gemini 3 Pro, 60/min.
No credit card, no expiry.

---

## In-container sign-in does not work

Choosing "Sign in with Google" inside the container produces:

```
Error 400: invalid_request — Required parameter is missing: response_type
```

The CLI builds an incomplete auth URL in a headless context, so Google rejects it before you can
sign in. Known upstream, still open
([#2515](https://github.com/google-gemini/gemini-cli/issues/2515),
[#3983](https://github.com/google-gemini/gemini-cli/issues/3983),
[#13853](https://github.com/google-gemini/gemini-cli/issues/13853)).
`NO_BROWSER=1` does not help — that path is broken too.

**Don't retry it.** It produces the same 400 every time. Use one of the two options below.

---

## Option 1 — API key (fastest)

Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey), then in the
container terminal:

```bash
echo 'GEMINI_API_KEY=paste-key-here' > ~/.gemini/.env
gemini
```

`~/.gemini` is a named volume, so this survives rebuilds and never touches your project folders.

**Limit:** ~250 requests/day, Flash models only.

---

## Option 2 — Google sign-in (4× the quota)

1,000 requests/day on Gemini 3 Pro. The sign-in has to happen on the **host**, where the browser
callback works normally.

```bash
npm install -g @google/gemini-cli              # on the HOST
gemini                                          # complete the browser sign-in
./.devcontainer/seed-credentials.sh gemini      # from a HOST terminal
```

That copies `~/.gemini/oauth_creds.json` into the container's credential volume.

---

## Harmless first-run noise

**`Failed to automatically enable IDE integration`** — the companion extension installs after your
terminal started. Open a new terminal and rerun.

**The "trust this folder" prompt** — that is Gemini's own setting about acting without asking. It
does not widen filesystem access, which is bounded by the container regardless of your answer.

---

## Where the credentials live

`/home/node/.gemini`, mounted from the named volume `agent-gemini-config`.

---

Next: **[Log in to Claude](04-login-claude.md)**
