from fastapi import APIRouter, Depends, Query

from ..deps import current_user
from ..services import audit as service

router = APIRouter(tags=["audit"])


@router.get("/ledger", summary="Append-only audit log, newest first")
def ledger(content_id: str | None = Query(default=None),
           user: dict = Depends(current_user)):
    return service.ledger(content_id)
