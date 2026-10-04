# ---- build stage: install dependencies into a virtualenv ----
FROM python:3.12-slim AS build
WORKDIR /app
RUN python -m venv /venv
# Copy only the dependency list first: this layer is cached until requirements.txt changes.
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# ---- runtime stage: small image, non-root user ----
FROM python:3.12-slim
# Set by CI (--build-arg): the app shows its version + commit at /api/info.
ARG APP_VERSION=dev
ARG GIT_SHA=local
ENV PATH="/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=$APP_VERSION \
    GIT_SHA=$GIT_SHA
WORKDIR /app
# Take only the installed packages from the build stage (no pip cache, no build tools).
COPY --from=build /venv /venv
COPY app ./app
# Run as a non-root user (the admission policy requires runAsNonRoot).
USER 10001
# Port 8080: non-root users cannot bind ports below 1024.
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
