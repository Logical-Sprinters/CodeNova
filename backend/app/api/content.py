from fastapi import APIRouter, Depends, HTTPException
from psycopg.errors import CheckViolation

from ..deps import current_user
from ..models.payloads import NewContent, NewVersion
from ..services import content as service

router = APIRouter(prefix="/content", tags=["content"])


@router.get("", summary="All copy, newest first, with its approval state")
def list_content(user: dict = Depends(current_user)):
    return service.list_content()


@router.post("", status_code=201, summary="Submit copy and run the check")
def create(body: NewContent, user: dict = Depends(current_user)):
    return service.create(body, user)


@router.get("/{content_id}", summary="Everything one screen needs, in one request")
def detail(content_id: str, user: dict = Depends(current_user)):
    try:
        return service.detail(content_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="content not found")


@router.post("/{content_id}/versions", status_code=201,
             summary="Create a new version (this voids any standing approval)")
def add_version(content_id: str, body: NewVersion, user: dict = Depends(current_user)):
    try:
        return service.add_version(content_id, body.text, user)
    except LookupError:
        raise HTTPException(status_code=404, detail="content not found")
    except CheckViolation as exc:
        raise HTTPException(status_code=422, detail=str(exc).splitlines()[0])


@router.post("/{content_id}/checks", summary="Re-run the check on the current version")
def recheck(content_id: str, user: dict = Depends(current_user)):
    try:
        detail = service.detail(content_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="content not found")
    return service.run_checks(detail["version"], detail["channel"])
