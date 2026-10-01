# ── Stage 1: deps ──────────────────────────────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# ── Stage 2: final ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS final
WORKDIR /app

# Non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=deps /app/node_modules ./node_modules
COPY src/ ./src/

# Build-time args injected by CI pipeline
ARG APP_VERSION=dev
ARG COLOR=unknown
ENV APP_VERSION=${APP_VERSION}
ENV COLOR=${COLOR}
ENV PORT=3000
ENV NODE_ENV=production

USER appuser
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=2 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/app.js"]
