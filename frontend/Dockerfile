# syntax=docker/dockerfile:1

# Static frontend served by Nginx.
#
# We use the *unprivileged* Nginx image (nginxinc/nginx-unprivileged): it runs
# as a non-root user (uid 101) and listens on 8080 by default, which is exactly
# what a hardened Kubernetes SecurityContext wants. No custom build step is
# needed because the frontend is plain HTML/CSS/JS.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Config template — envsubst expands ${BACKEND_URL} at container startup.
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

# Static assets.
COPY src/ /usr/share/nginx/html/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
