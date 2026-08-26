[← back to README](../README.md)

# 1. Set up in VS Code

## Prerequisites

1. **Docker Desktop** installed and running (WSL2 backend on Windows).
2. **VS Code** with the
   [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
   extension.

No API keys, no CLI install. Authentication is per-agent, done once, from inside the container.

---

## Where this folder goes

Copy this folder to your **workspace root** as `.devcontainer/`. Two rules:

1. It must be named **`.devcontainer`** — with the dot. That is the only path VS Code
   auto-discovers.
2. The **workspace root is the folder directly above it**. That is what you open in VS Code, and
   what `${localWorkspaceFolder}` resolves to in `devcontainer.json`.

```
<workspace-root>/          <- open THIS folder in VS Code
├── .devcontainer/         <- this folder
├── backend/               <- visible to agents only if listed in "mounts"
├── frontend/              <- visible to agents only if listed in "mounts"
└── <anything-else>/       <- invisible unless you list it
```

`backend/` and `frontend/` are just the defaults shipped in `devcontainer.json`. **The names mean
nothing to the sandbox** — rename them, use one folder or five, whatever suits your repo. All that
matters is that each one is listed in `mounts`.

> **Do not put this folder inside one of the project folders.** The mounts are written as
> `${localWorkspaceFolder}/<name>`, so if `.devcontainer/` sits in `backend/`, that resolves to
> `backend/backend` — Docker silently creates an empty folder and the agents see nothing.

The root itself is never mounted — only the children you list — so anything sitting beside
`.devcontainer/` stays invisible to every agent. **Anything outside the root is unreachable
entirely**, whether you list it or not.

Need more than one devcontainer at the same root? Move this into
`.devcontainer/ai-agents/devcontainer.json`; VS Code then shows a picker. Nothing else changes.

---

## Choosing what the agents can see

Open `devcontainer.json` and edit the `mounts` list. **This list *is* the sandbox boundary** —
one line per folder, nothing implicit.

Copy this template, replacing `FOLDER_NAME`:

```jsonc
"source=${localWorkspaceFolder}/FOLDER_NAME,target=/workspace/FOLDER_NAME,type=bind,consistency=cached",
```

- **Eligible folders** are the ones sitting directly inside the workspace root, beside
  `.devcontainer/`. Nothing above the root can be mounted, and nothing beside `.devcontainer/`
  is visible unless it has a line here.
- `${localWorkspaceFolder}` is the workspace root — leave it literal, do not substitute a path.
- Keep `target=` under `/workspace/`. The name after it is what the agents see.
- Append `,readonly` for anything they should read but never modify.
- Mounting a folder gets you everything beneath it — keep the list narrow.
- Leave `workspaceMount` alone. It is pinned to an empty named volume so `/workspace` starts bare
  and gains only what you list. Without that, the spec auto-mounts the entire workspace root.
- An empty list is a valid first boot: the container starts, agents just see no project code.

---

## Running it

Open the **workspace root** folder in VS Code, then:

> **F1** → `Dev Containers: Reopen in Container`

First run builds the image. From then on VS Code offers to reopen automatically.

Once it opens, use the integrated terminal exactly as you would any other:

```bash
codex
gemini
kimi
```

You will not get a terminal until the firewall self-test passes — `waitFor` is pinned to the
firewall step, so a failed self-test means **no shell** rather than an unconfined shell.

---

## Applying changes

Changes to `devcontainer.json`, `Dockerfile` or `allowed-domains.txt` need a **rebuild**:

> **F1** → `Dev Containers: Rebuild Container`

**Reload Window is not enough** — it reuses the existing container. `allowed-domains.txt` in
particular is `COPY`'d into the image at build time, so a running container keeps using the copy
it was built with. Editing the file and restarting changes nothing.

A normal rebuild is fine; changing a file invalidates its layer. "Rebuild Without Cache" is only
for reinstalling the agent CLIs.

To unblock a host *right now* without a rebuild, see
[Network allowlist](05-network-allowlist.md).

---

## Stopping it

Closing the CLI with **Ctrl+C** only quits that agent. The container keeps running and stays
logged in.

To actually stop it, close the VS Code window, then confirm on the host:

```bash
docker ps                 # nothing listed = stopped
docker stop <id>          # if it is still there
```

Stopping does not delete your logins — those live in named volumes and survive rebuilds.

---

Next: **[Log in to Codex](02-login-codex.md)** — free, and the one to start with.
