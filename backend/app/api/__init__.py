"""HTTP layer. Each module is a router; app.main mounts them all."""
from . import audit, content, findings, guidelines, health, identity, review

ROUTERS = (
    health.router,
    identity.router,
    guidelines.router,
    content.router,
    findings.router,
    review.router,
    audit.router,
)
