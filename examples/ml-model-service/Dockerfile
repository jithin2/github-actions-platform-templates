# Multi-stage build for a Python ML inference service.
# Builder installs dependencies; runtime image copies only site-packages and src.
# Keeps the production image free of pip, build tools, and test packages.
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

# Copy only installed packages from the builder
COPY --from=builder /install /usr/local

COPY src/ ./src/

# Non-root user — matches the runAsUser in the Kubernetes PodSpec
RUN useradd --no-create-home --uid 1000 appuser
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python", "-m", "uvicorn", "src.serve:app", "--host", "0.0.0.0", "--port", "8080"]
