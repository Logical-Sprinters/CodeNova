from fastapi import APIRouter, Depends, HTTPException
from psycopg.errors import CheckViolation

from ..deps import current_reviewer, current_user
from ..services import findings as findings_service
from ..services import review as service

router = APIRouter(tags=["review"])


@router.get("/queue", summary="What is waiting for a reviewer")
def queue(user: dict = Depends(current_user)):
    return service.queue()


@router.post("/content/{content_id}/approve", summary="Approve the current version")
def approve(content_id: str, user: dict = Depends(current_reviewer)):
    try:
        return service.approve(content_id, user)
    except LookupError:
        raise HTTPException(status_code=404, detail="content not found")
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=exc.args[0])
    except CheckViolation as exc:
        # The database refused: wrong role, author approving own work, or a hash that
        # does not match the version. Report its own words rather than a generic message.
        raise HTTPException(status_code=403, detail=str(exc).splitlines()[0])


@router.get("/clarity-tickets", summary="Rules that keep being overruled")
def clarity_tickets(user: dict = Depends(current_user)):
    return findings_service.clarity_tickets()
