# QwenPaw on Railway — a thin wrapper over the upstream image.
#
# Nothing is rebuilt here. Upstream's image is pinned and its three state
# directories are pointed at the Railway volume. The listener is left exactly
# as upstream sets it, for a reason worth spelling out — see below.
ARG QWENPAW_VERSION=v2.2.1
FROM agentscope/qwenpaw:${QWENPAW_VERSION}

# Upstream defaults all three directories under /app, which is image-local and
# discarded on every redeploy. They are all plain environment variables, so
# they consolidate onto the single volume mounted at /data.
ENV QWENPAW_WORKING_DIR=/data/working \
    QWENPAW_SECRET_DIR=/data/working.secret \
    QWENPAW_BACKUP_DIR=/data/working.backups \
    QWENPAW_PORT=8080

# NO socat relay, and no IPv6 rebind. Both were tried; this is the note that
# stops someone re-adding either one.
#
# 1. A relay would disable authentication. QwenPaw skips auth entirely for
#    peers on 127.0.0.1 and ::1, so anything that proxies inside the container
#    makes every request arrive looking local. Measured against v2.2.1:
#    GET /api/skills answers 200 from ::1 and 401 from a real peer.
#
# 2. Rebinding to `--host ::` does not work either. Python sets IPV6_V6ONLY,
#    so `::` is an IPv6-only socket, and Railway's public proxy reaches the
#    container over IPv4: measured, the edge returned 502 for every path while
#    the app answered 200 on [::1] from inside the same container.
#
# Upstream's own `--host 0.0.0.0` is therefore the correct binding here. The
# edge connects to it directly, the peer address is Railway's proxy rather
# than loopback, and the login is enforced — verified through the edge.
COPY --chmod=755 entrypoint.sh /usr/local/bin/railway-entrypoint
ENTRYPOINT ["/usr/local/bin/railway-entrypoint"]
