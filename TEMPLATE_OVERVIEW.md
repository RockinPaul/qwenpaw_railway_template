# Deploy and Host QwenPaw on Railway

[QwenPaw](https://github.com/agentscope-ai/QwenPaw) is a personal AI assistant you run yourself: a
web console with chat, long-term memory, skills, a plugin system, browser automation and an agent
that can run shell commands on your behalf. It connects to about twenty model providers, or to any
OpenAI- or Anthropic-compatible endpoint you point it at.

This template runs it on Railway with its working directory, its secrets and its backups on a single
volume, behind a login that is required rather than optional. One service, one volume, a public
domain.

## About Hosting QwenPaw

QwenPaw is a single Python service. The console, the API and the agent's tool calls all travel over
one HTTP port, so there is nothing to wire together — no database, no queue, no second container and
no media path. The container also runs a small X display so the agent can drive a real Chromium for
browser automation; it is machinery, not a screen you connect to.

Everything the assistant owns lives on the volume: `working` for conversations, memory and skills,
`working.secret` for provider credentials at mode 0700, and `working.backups`. Upstream defaults all
three under `/app`, where a redeploy would discard them, so this template points them at `/data`.

The part this template takes seriously is the login. QwenPaw ships with authentication off and
upstream's container entrypoint only prints a warning about it. On a public domain that warning
describes an agent with shell, filesystem and browser tools reachable by whoever finds the URL, so a
password is generated for your deployment and the container refuses to start without one.

## Why Deploy QwenPaw on Railway?

- **It stays awake.** Scheduled work and long agent runs continue with no machine of your own left on.
- **One service, no assembly.** No database, no broker, no sidecar.
- **Reachable from any browser**, including a phone, on the same conversations and memory.
- **Your own provider.** Bring a key for any of the preset providers, or point it at a custom
  OpenAI- or Anthropic-compatible endpoint. Usage stays between you and that provider.
- **It survives redeploys.** Conversations, memory, skills and credentials are on the volume.

## Common Use Cases

- An always-on personal assistant with memory that you reach from anywhere.
- Browser automation against a real Chromium, driven by the agent rather than a script.
- A private workspace for skills and plugins you would rather not run on a laptop.
- A shared assistant for a small team, behind one generated password.

## Dependencies for QwenPaw Hosting

- A model provider — an API key for one of the preset providers, or any OpenAI- or
  Anthropic-compatible endpoint.
- Nothing else: no database and no external services.

### Deployment Dependencies

- Upstream project: [agentscope-ai/QwenPaw](https://github.com/agentscope-ai/QwenPaw) (Apache-2.0),
  image `agentscope/qwenpaw:v2.2.1`.
- Upstream documentation: [QwenPaw docs](https://github.com/agentscope-ai/QwenPaw/tree/main/website/public/docs).
- Template source: [RockinPaul/qwenpaw_railway_template](https://github.com/RockinPaul/qwenpaw_railway_template) (MIT).

### Implementation Details

**After deploying:** copy `QWENPAW_AUTH_PASSWORD` from the service's Variables tab, open the public
domain and sign in as **`admin`**. Then add a provider key under Settings and pick a model.

**The password cannot be rotated from the variable.** Upstream creates the account on first boot and
then ignores the auto-registration variables entirely — measured: after changing the variable and
replacing the container, the original password still signed in and the new one returned 401. Change
the password from inside the console, not from the Variables tab.

**Why nothing proxies inside this container.** QwenPaw skips authentication for peers on
`127.0.0.1` and `::1`, so a relay in front of the app would make every request arrive looking local
and silently disable the login — measured against v2.2.1, `/api/skills` answers **200** from `::1`
and **401** from a real peer. Upstream's own `0.0.0.0` binding is therefore left exactly as it is:
Railway's edge connects to it directly, the peer address is the platform's proxy rather than
loopback, and the login is enforced. Rebinding to `::` was tried and is wrong here — Python sets
`IPV6_V6ONLY`, so the socket stops accepting the IPv4 connections Railway's public proxy makes.

**Security.** Measured through Railway's edge, not read from the docs: the console and
`/api/auth/status` are public so the sign-in page can load, `/api/skills` and the rest of the API
return **401** unauthenticated — including with a forged `X-Forwarded-For: 127.0.0.1`, because
upstream requires the direct TCP peer to be loopback as well — sign-in returns **401** on a wrong
password and **200** with a token on the right one, and that token then opens the API. The honest caveat: this is an agent with shell
and filesystem tools, so the blast radius of the URL is this container. Keep the generated password
and treat the link like an SSH session into a dev box.

**Local models.** QwenPaw can download a llama.cpp runtime and run a model in-container, and it does
work here — verified that upstream's pinned build loads on this image. Two things to know. It is
CPU-only on Linux by upstream's own code, so expect a few tokens per second and a bill for the RAM
it holds. And the model recommendation reads total host memory with no awareness of your service's
limit, so it will suggest the 9 GB-class models to everyone: choose by the memory you actually
provisioned. At the default 5 GB volume the 2B models and `QwenPaw-Flash-4B-Q4_K_M` fit; larger ones
need a larger volume. For most deployments a provider API key is faster and cheaper.

**Not available in a container.** The Computer Use plugin needs the QwenPaw desktop application on
Windows or macOS and a native helper reached over a local socket, so it is inert here. The agent's
shell appears in the console as an approve-or-reject tool card in chat, not an interactive terminal.

**Notes.** `PORT` is 8080 and the entrypoint passes it through; the healthcheck probes
`/api/auth/status` on that port and the domain targets it, so leave it alone. A clean shutdown exits
0, so the restart policy is `ALWAYS`. Idle memory is roughly 600 MB before any model or browser work.

## Licences

QwenPaw is Apache-2.0. The template's glue is MIT.
