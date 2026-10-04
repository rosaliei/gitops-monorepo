# ---- build stage: install production dependencies only ----
FROM node:24-alpine AS build
WORKDIR /app
# Copy only the dependency list first: this layer is cached until it changes.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---- runtime stage: small image, non-root user ----
FROM node:24-alpine
# Set by CI (--build-arg): the app shows its version + commit at /api/info.
ARG APP_VERSION=dev
ARG GIT_SHA=local
ENV NODE_ENV=production \
    APP_VERSION=$APP_VERSION \
    GIT_SHA=$GIT_SHA
# Patch OS packages and drop npm: the runtime only needs node. Smaller image, fewer CVEs.
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /opt/yarn* /usr/local/bin/yarn*
WORKDIR /app
# Take only the installed packages from the build stage.
COPY --from=build /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
# Run as a non-root user (the admission policy requires runAsNonRoot).
USER 10001
# Port 8080: non-root users cannot bind ports below 1024.
EXPOSE 8080
CMD ["node", "src/server.js"]
