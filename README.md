# QwenPaw on Railway

[QwenPaw](https://github.com/agentscope-ai/QwenPaw) — a self-hosted personal AI assistant with a web
console, long-term memory, skills, plugins, browser automation and an agent that runs shell commands
— on Railway, with its state on a volume and a login that is required rather than optional.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/qwenpaw-1)

## Service

| Service | Base | Public | Role |
|---|---|---|---|
| `qwenpaw` | `agentscope/qwenpaw:v2.2.1` | **yes** | Console, API, agent, browser automation — one process tree under supervisord. |

One service, one volume. The image also runs Xvfb and xfce4 so the agent can drive a headed
Chromium; there is no VNC or noVNC and that display is not viewable by design.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `QWENPAW_AUTH_PASSWORD` | generated, 24 chars | Console sign-in for `admin`. Read it from the service variables after deploying. |
| `QWENPAW_AUTH_USERNAME` | `admin` | The account created on first boot. |
| `QWENPAW_AGENT_LANGUAGE` | `en` | Language of the agent's persona files, chosen on first boot only. `en`, `zh`, `ru` or `id`. |
| `PORT` | `8080` | The port Railway's healthcheck probes and the domain targets. Leave it alone. |
| `QWENPAW_WORKING_DIR` | `/data/working` | Baked. Conversations, memory, skills, local models. |
| `QWENPAW_SECRET_DIR` | `/data/working.secret` | Baked. Provider credentials, mode 0700. |
| `QWENPAW_BACKUP_DIR` | `/data/working.backups` | Baked. |

The deploy form asks for nothing you have to invent.

## First run

1. Copy `QWENPAW_AUTH_PASSWORD` from the service's **Variables** tab.
2. Open the public domain and sign in as **`admin`**.
3. Add a provider key under **Settings → Models** and pick a default model.

**The agent's language is also first-boot only.** Upstream defaults to `zh` and has no environment
variable or init flag for it, so an unconfigured deployment gets a Chinese-speaking agent. This
template seeds `QWENPAW_AGENT_LANGUAGE` (default `en`) into `config.json` before the first
initialisation, which is the only moment the choice is free — afterwards the persona files are on the
volume and upstream's non-interactive init copies with `skip_existing=True`, so it will not replace
them. Set it before you deploy, or create a new agent in the console with the language you want.

**The password variable is write-once.** Upstream creates the account on first boot and then ignores
the auto-registration variables. Measured: after changing `QWENPAW_AUTH_PASSWORD` and replacing the
container, the original password still returned 200 and the new one 401. Rotate the password from
inside the console instead.

## Security

The login is **required** here, which is stricter than upstream's default and deliberately so.
QwenPaw ships with authentication off, and upstream's own container entrypoint only prints a warning.
On a public domain that warning describes an agent with shell, filesystem and browser tools open to
anyone who finds the URL, so the entrypoint refuses to start without a password of at least 12
characters, and refuses to start at all if authentication is explicitly disabled.

Measured against a running instance from a real network peer:

- `/api/skills` and the rest of the API return **401** unauthenticated, and still **401** with a
  forged `X-Forwarded-For: 127.0.0.1` or `X-Real-IP: 127.0.0.1` — upstream requires the direct TCP
  peer to be loopback too, so the bypass is not reachable by header spoofing.
- `/` and `/api/auth/status` return **200** — the console shell and the sign-in probe are public so
  the login page can load. `/api/auth/status` reports only `{"enabled":true,"has_users":true}`.
- Sign-in returns **401** on a wrong password and **200** with a bearer token on the right one, and
  that token then opens `/api/skills`.
- Railway's `Host: healthcheck.railway.app` probe answers 200 without credentials.

The honest caveat: this is an agent with shell and filesystem tools. The blast radius of the URL is
this container. Keep the generated password and treat the link accordingly. Upstream ships a Tool
Guard approval flow, a File Guard, a skill scanner and an access policy on top —
see [Security](https://github.com/agentscope-ai/QwenPaw/blob/main/website/public/docs/security.en.md).

## Why it is shaped this way

- **No relay, and upstream's `0.0.0.0` left alone.** A `socat` relay is the usual fix in this
  portfolio, and here it would be a security hole: QwenPaw skips authentication for `127.0.0.1` and
  `::1`, so a relay makes every request look local. Measured: `/api/skills` returns **200** from
  `::1` and **401** from a real peer. With nothing proxying inside the container, Railway's edge is
  the peer and the login is enforced.
- **Rebinding to `::` was tried and is wrong.** Python sets `IPV6_V6ONLY`, so `--host ::` is an
  IPv6-only socket, and Railway's *public* proxy reaches the container over IPv4: the edge returned
  **502** on every path while the app answered **200** on `[::1]` inside the same container. IPv6 is
  what private networking between services needs, not what a public domain uses.
- **Three directories, one volume.** All three are plain environment variables, so they consolidate
  onto `/data` instead of being lost under `/app` on redeploy.
- **`restartPolicyType: ALWAYS`.** A clean `SIGTERM` exits `0`, which `ON_FAILURE` would not restart.
- **Healthcheck on `/api/auth/status`.** It is public by necessity and proves the app is serving,
  which `/` alone does not.

## What persists

`/data` holds `working/`, `working.secret/` (0700) and `working.backups/`. Verified by replacing the
container: a file written before the swap was still there afterwards, the config was found rather
than re-initialised, and the original password still signed in.

## Local models

QwenPaw can download a llama.cpp runtime into `working/local_models` and serve a model in-container.
It works here — upstream's pinned `b8744` build loads against this image's glibc on `amd64`, which is
what Railway runs. Caveats worth knowing before you rely on it:

- **CPU only.** Upstream's backend resolver returns `cpu` for Linux unconditionally; the CUDA path is
  Windows-exclusive, and Railway has no GPU regardless.
- **The hardware recommendation is wrong in a container.** It reads total system memory with no
  cgroup awareness, so it reports the host's RAM rather than your service's limit and recommends the
  9B tier to everyone. Pick by the memory you actually provisioned.
- **Volume sizing.** `QwenPaw-Flash-2B-Q4_K_M` is 1.56 GB and `-4B-Q4_K_M` is 3.07 GB, so both fit
  the default 5 GB volume. The 9B models (5.48 GB and 10.59 GB) do not.
- On `arm64` hosts the same builds fail against Debian 12's glibc — irrelevant on Railway, relevant
  if you run this image on Apple Silicon.

For most deployments a provider API key is faster and cheaper than CPU inference you pay to keep
resident.

## Known limits

The **Computer Use** plugin is a desktop feature: upstream supports it on Windows and macOS only,
backed by a native helper shipped with the desktop application and reached over a named pipe or Unix
socket. It cannot work in a container. The agent's **shell** is a tool card in chat with an approval
flow, not an interactive terminal — the console ships no terminal emulator.

## Upgrading

Bump `QWENPAW_VERSION` in the `Dockerfile` and push. The wrapper touches nothing inside the image
beyond environment variables and an entrypoint, so a version bump is usually the whole change. The
one thing to re-check on a major bump is that upstream still binds `0.0.0.0` — a switch to an
IPv6-only default would make the service unreachable from Railway's edge.

## Licences

QwenPaw is [Apache-2.0](https://github.com/agentscope-ai/QwenPaw/blob/main/LICENSE). The glue in this
repository is MIT.
