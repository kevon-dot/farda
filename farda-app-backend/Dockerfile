# syntax=docker/dockerfile:1
FROM node:24.12.0-bookworm-slim AS base
ARG BUILD_VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="Farda API" \
      org.opencontainers.image.version="$BUILD_VERSION" \
      org.opencontainers.image.revision="$VCS_REF" \
      org.opencontainers.image.created="$BUILD_DATE" \
      org.opencontainers.image.source="https://github.com/kevon-dot/farda"
ENV NODE_ENV=production \
    BUILD_VERSION=$BUILD_VERSION \
    COMMIT_SHA=$VCS_REF \
    BUILD_DATE=$BUILD_DATE \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH
RUN npm install --global pnpm@11.25.0
WORKDIR /app

FROM base AS dependencies
ENV NODE_ENV=development
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

FROM dependencies AS build
COPY . .
# Prisma generation validates URL syntax but does not connect. This placeholder
# keeps image builds credential-free; runtime and migration jobs still require
# DATABASE_URL from their secret store.
RUN DATABASE_URL=postgresql://build:build@127.0.0.1:5432/build pnpm build

# Run this target as a one-shot release job before updating application tasks.
FROM build AS migration
ENV NODE_ENV=production
CMD ["pnpm", "db:migrate"]

FROM base AS runtime
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --prod --frozen-lockfile
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/generated ./generated
USER node
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=4s --start-period=15s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:'+(process.env.PORT||8000)+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]
CMD ["node", "-r", "module-alias/register", "dist/main.js"]
