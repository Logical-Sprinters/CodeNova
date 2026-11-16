"""BrandGuard API: authenticated mobile workflows and server-owned storage."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import initialize_data_store
from app import config
from app.http_security import CONTENT_SECURITY_POLICY, DOCUMENTATION_SECURITY_POLICY
from app.routers.authentication import router as auth_router
from app.routers.recovery import router as recovery_router
from app.routers.email_delivery import router as email_router
from app.routers.library import router as library_router
from app.routers.workspace import router as workspace_router
from app.routers.files import router as files_router
from app.routers.audit import router as audit_router
from app.routers.brand import router as brand_router
from app.routers.receipts import router as receipts_router
from app.routers.reviews import router as reviews_router


@asynccontextmanager
async def lifespan(app):
    initialize_data_store()
    yield


app = FastAPI(
    title="BrandGuard API",
    version="2.0.0",
    lifespan=lifespan,
    description="Password/token authentication, transactional data, brand libraries, grounded-provider integration, drafts and live activity. Cloud/provider configuration is explicit.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(auth_router)
app.include_router(recovery_router)
app.include_router(email_router)
app.include_router(library_router)
app.include_router(workspace_router)
app.include_router(files_router)
app.include_router(brand_router)
app.include_router(reviews_router)
app.include_router(receipts_router)
app.include_router(audit_router)


@app.get("/")
async def root():
    return {
        "message": "Welcome to BrandGuard API",
        "status": "running",
        "docs": "/docs",
    }


@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "BrandGuard API", "version": "2.0.0"}


@app.middleware("http")
async def private_response_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = (
        DOCUMENTATION_SECURITY_POLICY
        if request.url.path in {"/docs", "/docs/oauth2-redirect", "/redoc"}
        else CONTENT_SECURITY_POLICY
    )
    if config.PUBLIC_APP_URL.startswith("https://"):
        response.headers["Strict-Transport-Security"] = "max-age=31536000"
    if request.url.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"
    return response
