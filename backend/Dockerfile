# syntax=docker/dockerfile:1

# ---- Stage 1: install production dependencies ----
# A dedicated stage keeps devDependencies (jest, supertest) out of the final
# image, shrinking it and reducing attack surface.
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
# `npm ci` is reproducible (installs exactly what the lockfile pins).
# `--omit=dev` skips test tooling. If no lockfile exists yet, fall back to install.
RUN npm ci --omit=dev || npm install --omit=dev

# ---- Stage 2: minimal runtime ----
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Copy pre-built node_modules and application source.
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Run as the unprivileged, built-in `node` user rather than root.
USER node

EXPOSE 8080

# Container-level healthcheck (independent of Kubernetes probes) — useful for
# docker-compose and `docker ps` status.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:8080/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "src/server.js"]
