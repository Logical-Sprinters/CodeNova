FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*
COPY backend/requirements.txt /app/requirements.txt
RUN python -m pip install --no-cache-dir -r /app/requirements.txt \
    && groupadd --system brandguard \
    && useradd --system --gid brandguard --home /app brandguard
COPY backend /app/backend
COPY browser_preview /app/browser_preview
COPY serve.py /app/serve.py
RUN mkdir -p /tmp/brandguard && chown brandguard:brandguard /tmp/brandguard
USER brandguard
WORKDIR /app/backend
EXPOSE 8080
CMD ["python", "/app/serve.py"]
