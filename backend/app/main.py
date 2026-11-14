
"""FastAPI application entry point."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers.brand import router as brand_router
from app.routers.reviews import router as reviews_router
from app.routers.receipts import router as receipts_router

app = FastAPI(
    title="BrandGuard API",
    description="Backend API for BrandGuard.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(brand_router)
app.include_router(reviews_router)
app.include_router(receipts_router)


@app.get("/")
async def root():
    return {
        "message": "Welcome to BrandGuard API",
        "status": "running",
    }


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "BrandGuard API",
    }
