"""orders-api: a tiny order service used to demo CI/CD and GitOps.

Endpoints
  GET  /healthz      liveness probe
  GET  /readyz       readiness probe
  GET  /metrics      Prometheus metrics
  GET  /api/info     which version is running where
  GET  /api/orders   list orders
  POST /api/orders   create an order
"""

import os
import time

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field

SERVICE = "orders-api"
VERSION = os.getenv("APP_VERSION", "dev")
COMMIT = os.getenv("GIT_SHA", "local")
ENVIRONMENT = os.getenv("APP_ENV", "local")

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "route"])
BUILD_INFO = Gauge("app_build_info", "Build information", ["service", "version", "commit"])
BUILD_INFO.labels(SERVICE, VERSION, COMMIT).set(1)

app = FastAPI(title=SERVICE, version=VERSION)


class OrderIn(BaseModel):
    item: str = Field(min_length=1)
    quantity: int = Field(gt=0, le=100)


ORDERS: list[dict] = []


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    path = route.path if route else "unmatched"
    if path != "/metrics":
        LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
        REQUESTS.labels(request.method, path, str(response.status_code)).inc()
    return response


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/info")
def info():
    return {
        "service": SERVICE,
        "version": VERSION,
        "commit": COMMIT,
        "environment": ENVIRONMENT,
        # Injected from a Kubernetes Secret (External Secrets Operator). Never echo the value.
        "secretConfigured": bool(os.getenv("API_KEY")),
    }


@app.get("/api/orders")
def list_orders():
    return ORDERS


@app.post("/api/orders", status_code=201)
def create_order(order: OrderIn):
    if order.item.lower() == "error":
        # Handy for demoing the error-rate alert: POST {"item": "error", "quantity": 1}
        raise HTTPException(status_code=500, detail="simulated failure")
    record = {"id": len(ORDERS) + 1, **order.model_dump()}
    ORDERS.append(record)
    return record
