# QwenPaw on Railway — a thin wrapper over the upstream image.
#
# Nothing is rebuilt here. Upstream's image is pinned, its three state
# directories are pointed at the Railway volume, and the app's listener is
# moved off 0.0.0.0 so it is reachable over Railway's IPv6-only private
# network without a relay in front of it.
ARG QWENPAW_VERSION=v2.2.1
FROM agentscope/qwenpaw:${QWENPAW_VERSION}

# Upstream defaults all three directories under /app, which is image-local and
# discarded on every redeploy. They are all plain environment variables, so
# they consolidate onto the single volume mounted at /data.
ENV QWENPAW_WORKING_DIR=/data/working \
    QWENPAW_SECRET_DIR=/data/working.secret \
    QWENPAW_BACKUP_DIR=/data/working.backups \
    QWENPAW_PORT=8080

# Bind :: instead of 0.0.0.0.
#
# Railway's private network is IPv6-only, and upstream's supervisord template
# starts the app with `--host 0.0.0.0`, which never accepts an IPv6 connection.
# The usual fix in this portfolio is a socat relay; here that would be a
# security hole rather than a workaround. QwenPaw skips authentication for
# peers on 127.0.0.1 and ::1, so every relayed request arrives looking local
# and the login is silently bypassed. Measured against v2.2.1: GET /api/skills
# answers 401 from a real peer and 200 through a relay.
#
# The grep is the important half. If a future upstream version renames or
# rewrites this template the sed matches nothing; without the check that
# regresses quietly to an unreachable IPv4-only listener, with it the build
# fails here instead.
RUN sed -i 's/--host 0\.0\.0\.0/--host ::/' \
        /etc/supervisor/conf.d/supervisord.conf.template \
 && grep -q -- '--host ::' /etc/supervisor/conf.d/supervisord.conf.template

COPY --chmod=755 entrypoint.sh /usr/local/bin/railway-entrypoint
ENTRYPOINT ["/usr/local/bin/railway-entrypoint"]
