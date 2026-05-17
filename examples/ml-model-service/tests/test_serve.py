"""Tests for the ML model inference endpoint."""

import pytest
from fastapi.testclient import TestClient

from src.serve import app

client = TestClient(app)


def test_health_returns_ok() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_predict_returns_valid_response() -> None:
    response = client.post("/predict", json={"features": [1.0, 2.0, 3.0]})
    assert response.status_code == 200
    body = response.json()
    assert "prediction" in body
    assert "confidence" in body
    assert "model_version" in body
    assert isinstance(body["prediction"], float)
    assert 0.0 <= body["confidence"] <= 1.0


def test_predict_single_feature() -> None:
    response = client.post("/predict", json={"features": [5.0]})
    assert response.status_code == 200
    assert response.json()["prediction"] == 5.0


def test_predict_empty_features_returns_422() -> None:
    # Pydantic validator rejects empty features list before the handler runs.
    response = client.post("/predict", json={"features": []})
    assert response.status_code == 422


def test_predict_missing_body_returns_422() -> None:
    response = client.post("/predict", json={})
    assert response.status_code == 422


@pytest.mark.parametrize("features,expected", [
    ([0.0, 0.0], 0.0),
    ([10.0, 20.0], 15.0),
    ([1.0], 1.0),
])
def test_predict_mean_calculation(features: list[float], expected: float) -> None:
    response = client.post("/predict", json={"features": features})
    assert response.status_code == 200
    assert response.json()["prediction"] == expected
