# ---- build stage: install production dependencies only ----
FROM node:25-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---- runtime stage: small image, non-root user ----
FROM node:25-alpine
ARG APP_VERSION=dev
ARG GIT_SHA=local
ENV NODE_ENV=production \
    APP_VERSION=$APP_VERSION \
    GIT_SHA=$GIT_SHA
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
USER 10001
EXPOSE 8080
CMD ["node", "src/server.js"]
