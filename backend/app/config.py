"""Configuration. There is no model API key here on purpose: the checker is deterministic."""
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://brandguard:brandguard@localhost:5432/brandguard",
)
APP_NAME = "BrandGuard API"
APP_VERSION = "1.0.0"
