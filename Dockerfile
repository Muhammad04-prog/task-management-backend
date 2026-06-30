# Multi-stage build for the Task Management API.
#
# 1. build-deps — install all deps (incl. dev) for building
# 2. builder    — generate Prisma client + tsc compile to dist/
# 3. prod-deps  — install only production dependencies
# 4. runtime    — slim image copying dist + prod-deps node_modules + Prisma client

# --- build-deps --------------------------------------------------------------
FROM node:20-slim AS build-deps
WORKDIR /app
# OpenSSL is required by Prisma's query engine.
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN npm ci

# --- builder -----------------------------------------------------------------
FROM build-deps AS builder
WORKDIR /app
COPY . .
RUN npx prisma generate && npm run build

# --- prod-deps ---------------------------------------------------------------
FROM node:20-slim AS prod-deps
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# --- runtime -----------------------------------------------------------------
FROM node:20-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*

# Copy production node_modules
COPY --from=prod-deps /app/node_modules ./node_modules

# Compiled app + generated Prisma client + schema (needed for migrate deploy).
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma/client ./node_modules/@prisma/client
COPY --from=builder /app/src/prisma ./src/prisma

USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]

