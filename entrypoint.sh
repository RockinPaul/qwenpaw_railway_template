#!/bin/sh
set -eu

# Railway names the port in PORT; upstream reads QWENPAW_PORT and substitutes
# it into the supervisord config. Bridge the two so the healthcheck, the
# domain's target port and the listener cannot drift apart.
export QWENPAW_PORT="${PORT:-8080}"

# ---------------------------------------------------------------------------
# Fail closed on authentication
# ---------------------------------------------------------------------------
# QwenPaw ships with authentication off, and upstream's container entrypoint
# only prints a warning about it. On a public Railway domain that warning
# describes an agent with a shell tool, a filesystem and a browser, reachable
# by anyone who finds the URL. So the credentials are required here and the
# container refuses to start without them.
#
# There is a second reason the gate has to hold: QwenPaw skips authentication
# entirely for requests from 127.0.0.1 and ::1. That is why nothing proxies
# inside this container — see the Dockerfile. Railway's proxy connects to the
# app directly, so the peer address is never loopback and the login is the
# only way in.
case "$(printf '%s' "${QWENPAW_AUTH_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes) ;;
    *)
        echo "FATAL: QWENPAW_AUTH_ENABLED is set to '${QWENPAW_AUTH_ENABLED}'." >&2
        echo "  Authentication cannot be disabled in this template. QwenPaw is an" >&2
        echo "  agent with shell, filesystem and browser tools, and this service has" >&2
        echo "  a public domain — without the login, anyone who finds the URL has" >&2
        echo "  all three. Remove the variable to use the template's default." >&2
        exit 1
        ;;
esac
export QWENPAW_AUTH_ENABLED=true

if [ -z "${QWENPAW_AUTH_USERNAME:-}" ]; then
    echo "FATAL: QWENPAW_AUTH_USERNAME is empty." >&2
    echo "  It is the admin account created on first boot. The template sets it." >&2
    exit 1
fi
if [ -z "${QWENPAW_AUTH_PASSWORD:-}" ] || \
   [ "$(printf '%s' "${QWENPAW_AUTH_PASSWORD}" | wc -c)" -lt 12 ]; then
    echo "FATAL: QWENPAW_AUTH_PASSWORD is empty or shorter than 12 characters." >&2
    echo "  It is the password for '${QWENPAW_AUTH_USERNAME}'. The template" >&2
    echo "  generates one; read it from the service's Variables tab." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Volume layout
# ---------------------------------------------------------------------------
# Railway mounts the volume root-owned with a lost+found directory, so state
# lives in subdirectories beside it. Upstream creates the secret directory at
# 0700 itself; these only have to exist so its first-boot init can write into
# them. The auto-registration variables above are ignored by upstream once an
# account exists, so a redeploy onto a populated volume is a no-op.
mkdir -p "${QWENPAW_WORKING_DIR}" "${QWENPAW_SECRET_DIR}" "${QWENPAW_BACKUP_DIR}"

# ---------------------------------------------------------------------------
# Agent language, which can only be chosen before the first init
# ---------------------------------------------------------------------------
# Upstream's AgentsConfig.language defaults to "zh" and there is no environment
# variable and no `qwenpaw init` flag for it. That setting decides which persona
# files (AGENTS.md, SOUL.md, PROFILE.md and the rest of system_prompt_files) are
# copied into the default workspace, so a deployment that takes the default gets
# a Chinese-speaking agent.
#
# It cannot be corrected afterwards from the console: the only code path that
# re-copies those files on a language change is an interactive `qwenpaw init`
# or one with --force, and the non-interactive `--defaults` path upstream's
# entrypoint uses copies with skip_existing=True. Once the files are on the
# volume they stay. Seeding config.json before the first init is the one moment
# the choice is free, so the template takes it.
AGENT_LANG="${QWENPAW_AGENT_LANGUAGE:-en}"
case "${AGENT_LANG}" in
    en|zh|ru|id) ;;
    *)
        echo "FATAL: QWENPAW_AGENT_LANGUAGE is '${AGENT_LANG}', which upstream does not ship." >&2
        echo "  Persona files exist for: en, zh, ru, id. An unknown value would leave the" >&2
        echo "  agent with no persona at all, so this fails rather than starting broken." >&2
        exit 1
        ;;
esac

CONFIG_FILE="${QWENPAW_WORKING_DIR}/config.json"
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "qwenpaw: first boot, seeding agent language '${AGENT_LANG}' before init"
    printf '{"agents":{"language":"%s"}}\n' "${AGENT_LANG}" > "${CONFIG_FILE}"
    # Run the initialiser here rather than letting upstream's entrypoint do it,
    # because it only runs when config.json is absent and the seed has just
    # created it. If it fails, drop the seed so upstream's own path still runs.
    if ! qwenpaw init --defaults --accept-security; then
        echo "qwenpaw: seeded init failed, falling back to upstream defaults" >&2
        rm -f "${CONFIG_FILE}"
    fi
fi

echo "qwenpaw: state at ${QWENPAW_WORKING_DIR}, secrets at ${QWENPAW_SECRET_DIR}"
echo "qwenpaw: serving on 0.0.0.0:${QWENPAW_PORT} with login required as '${QWENPAW_AUTH_USERNAME}'"

exec /entrypoint.sh "$@"
