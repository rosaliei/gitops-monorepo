from fastapi.testclient import TestClient

from app.main import ORDERS, app

client = TestClient(app)


def setup_function():
    ORDERS.clear()


def test_health_probes():
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").json() == {"status": "ready"}


def test_info_reports_version_and_environment():
    body = client.get("/api/info").json()
    assert body["service"] == "orders-api"
    assert {"version", "commit", "environment", "secretConfigured"} <= body.keys()


def test_create_and_list_orders():
    created = client.post("/api/orders", json={"item": "coffee", "quantity": 2})
    assert created.status_code == 201
    assert created.json() == {"id": 1, "item": "coffee", "quantity": 2}
    assert client.get("/api/orders").json() == [created.json()]


def test_rejects_invalid_quantity():
    assert client.post("/api/orders", json={"item": "tea", "quantity": 0}).status_code == 422


def test_simulated_failure_returns_500():
    assert client.post("/api/orders", json={"item": "error", "quantity": 1}).status_code == 500


def test_metrics_are_exposed():
    client.get("/healthz")
    text = client.get("/metrics").text
    assert 'http_requests_total{method="GET",route="/healthz",status="200"}' in text
    assert "app_build_info" in text
