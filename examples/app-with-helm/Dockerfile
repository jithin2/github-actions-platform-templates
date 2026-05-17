# Multi-stage build — builder installs deps, final image copies only the output.
# Keeps the production image small and free of build tooling.
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
# ci instead of install: uses package-lock.json exactly, fails on mismatch
RUN npm ci --only=production

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM node:20-alpine

WORKDIR /app

# Copy only the installed modules from the builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY src/ ./src/

# Run as non-root — required by the Helm chart's securityContext
USER node

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/index.js"]
