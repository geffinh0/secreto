# Atila's Client - backend (FastAPI + SQLite). Built from the repo root so it
# can COPY just backend/, keeping the huge reverse-engineering dumps and the
# Flutter source out of this image entirely (see .dockerignore).
FROM python:3.12-slim

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ .

# The SQLite DB lives on a mounted volume (see docker-compose.yml) so it
# survives image rebuilds/redeploys - never bake real data into the image.
RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && mkdir -p /data \
    && chown -R appuser:appuser /data /app
USER appuser

ENV SM_HOST=0.0.0.0 \
    SM_PORT=8000 \
    SM_DB_PATH=/data/super_moderator.db

EXPOSE 8000

CMD ["python", "main.py"]
