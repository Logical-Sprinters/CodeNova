# Dockerfile for BrandGuard FastAPI backend
FROM python:3.10-slim

# Set a non‑root user for security
RUN useradd -m appuser
WORKDIR /app

# Install runtime dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose the port FastAPI will run on (uvicorn default)
EXPOSE 8000

# Switch to non‑root user
USER appuser

# Run the FastAPI server
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
