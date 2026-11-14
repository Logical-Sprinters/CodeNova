from fastapi import APIRouter, Depends, HTTPException
from psycopg.errors import CheckViolation

from ..deps import current_user
from ..models.payloads import OverrideRequest
from ..services import findings as service

router = APIRouter(prefix="/findings", tags=["findings"])


@router.get("/{finding_id}/rewrites", summary="The three repairs for one finding")
def rewrites(finding_id: str, user: dict = Depends(current_user)):
    return service.rewrites(finding_id)


@router.post("/{finding_id}/rewrites/{option_label}", status_code=201,
             summary="Accept a repair: creates a new version and voids the approval")
def accept_rewrite(finding_id: str, option_label: str, user: dict = Depends(current_user)):
    try:
        return service.accept_rewrite(finding_id, option_label, user)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=exc.args[0])


@router.post("/{finding_id}/override", status_code=201,
             summary="Override with a reason; recorded against the rule version")
def override(finding_id: str, body: OverrideRequest, user: dict = Depends(current_user)):
    try:
        return service.override(finding_id, body, user)
    except LookupError:
        raise HTTPException(status_code=404, detail="finding not found")
    except CheckViolation as exc:
        raise HTTPException(status_code=422, detail=str(exc).splitlines()[0])
