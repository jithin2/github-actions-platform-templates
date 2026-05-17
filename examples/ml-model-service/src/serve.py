"""Minimal FastAPI inference endpoint for a regression model.

In a real service this module would load a model from a model registry
(e.g. MLflow, Vertex AI Model Registry) at startup and serve predictions.
The placeholder implementation is kept simple so the tests are clear.
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, field_validator

app = FastAPI(title="ML Model Service", version="1.0.0")


class PredictRequest(BaseModel):
    features: list[float]

    @field_validator("features")
    @classmethod
    def features_must_not_be_empty(cls, v: list[float]) -> list[float]:
        if not v:
            raise ValueError("features must contain at least one value")
        return v


class PredictResponse(BaseModel):
    prediction: float
    confidence: float
    model_version: str


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/predict", response_model=PredictResponse)
def predict(request: PredictRequest) -> PredictResponse:
    # Placeholder — production implementation loads from model registry.
    prediction = sum(request.features) / len(request.features)
    return PredictResponse(
        prediction=round(prediction, 4),
        confidence=0.95,
        model_version="1.0.0",
    )
