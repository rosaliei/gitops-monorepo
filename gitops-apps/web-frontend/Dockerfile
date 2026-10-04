# Unprivileged nginx: runs as a non-root user and listens on 8080.
FROM nginxinc/nginx-unprivileged:1.29-alpine
# Set by CI (--build-arg): written into version.json below.
ARG APP_VERSION=dev
ARG GIT_SHA=local
# NGINX_ENTRYPOINT_LOCAL_RESOLVERS makes the image export the pod's DNS server as NGINX_LOCAL_RESOLVERS.
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
    APP_ENV=local \
    ORDERS_API_HOST=orders-api \
    INVENTORY_HOST=inventory-svc
# nginx config with ${VARIABLES}, filled in at container start.
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
# The static status page.
COPY public/ /usr/share/nginx/html/
# Briefly root to write version.json, then back to the unprivileged nginx user (101).
USER root
RUN printf '{"version":"%s","commit":"%s"}' "$APP_VERSION" "$GIT_SHA" > /usr/share/nginx/html/version.json
USER 101
EXPOSE 8080
