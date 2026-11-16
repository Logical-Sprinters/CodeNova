"""Private TXT/Markdown/PDF storage and extraction. No fake image/OCR support."""

from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from urllib.parse import quote
from uuid import uuid4

import httpx
from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from fastapi.responses import Response
from pypdf import PdfReader

from app import config
from app.auth import can_read, get_user, require_reviewer
from app.storage import STORE_LOCK, read_json, write_json

router = APIRouter(prefix="/api/v1/files", tags=["Private document storage"])
MAX_BYTES = 5 * 1024 * 1024


def extract(filename, raw):
    suffix = Path(filename).suffix.lower()
    try:
        if suffix in {".txt", ".md"}:
            text = raw.decode("utf-8-sig")[:100000]
            if not text.strip():
                raise HTTPException(422, "The document has no readable text")
            return text, "text/plain; charset=utf-8"
        if suffix == ".pdf" and raw.startswith(b"%PDF"):
            reader = PdfReader(BytesIO(raw))
            if reader.is_encrypted or len(reader.pages) > 30:
                raise HTTPException(422, "Use an unencrypted PDF with at most 30 pages")
            text = "\n".join(page.extract_text() or "" for page in reader.pages)[
                :100000
            ]
            if not text.strip():
                raise HTTPException(
                    422,
                    "No text was extracted. Scanned/image PDFs need OCR, which is not configured.",
                )
            return text, "application/pdf"
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(
            422, "Cannot extract readable UTF-8/PDF text from this document"
        ) from error
    raise HTTPException(
        415,
        "Supported uploads: .txt, .md and text-based .pdf only. Image OCR is not configured.",
    )


def storage_request(method, key, token, raw=None, mime=None):
    if not config.SUPABASE_URL or not config.SUPABASE_PUBLISHABLE_KEY:
        raise HTTPException(503, "Supabase storage is not configured")
    url = f'{config.SUPABASE_URL}/storage/v1/object/{quote(config.SUPABASE_STORAGE_BUCKET, safe="")}/{quote(key, safe="/")}'
    headers = {
        "apikey": config.SUPABASE_PUBLISHABLE_KEY,
        "Authorization": f"Bearer {token}",
    }
    if mime:
        headers["Content-Type"] = mime
    try:
        result = httpx.request(method, url, headers=headers, content=raw, timeout=25)
        result.raise_for_status()
        return result.content
    except httpx.HTTPError as error:
        raise HTTPException(
            503,
            "Private storage request failed. Check the bucket/policies and Supabase configuration.",
        ) from error


@router.post("", status_code=201)
async def upload(
    file: UploadFile = File(...),
    as_fact: bool = False,
    brand_name: str = "Acme",
    user=Depends(get_user),
    authorization: str = Header(),
):
    if as_fact:
        require_reviewer(user)
    raw = await file.read(MAX_BYTES + 1)
    if not raw or len(raw) > MAX_BYTES:
        raise HTTPException(413, "Upload a nonempty document no larger than 5 MB")
    name = Path((file.filename or "document.txt").replace("\\", "/")).name[:160]
    content, mime = extract(name, raw)
    asset_id = str(uuid4())
    key = f'{user["user_id"]}/{asset_id}{Path(name).suffix.lower()}'
    if config.AUTH_PROVIDER == "supabase":
        storage_request("POST", key, authorization.split(" ", 1)[1], raw, mime)
    else:
        target = config.DATA_DIR / "uploads" / key
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    with STORE_LOCK:
        asset = {
            "id": asset_id,
            "creator_id": user["user_id"],
            "name": name,
            "storage_key": key,
            "bytes": len(raw),
            "content_type": mime,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        items = read_json(config.DATA_DIR / "assets.json", [])
        items.append(asset)
        write_json(config.DATA_DIR / "assets.json", items)
        fact = None
        if as_fact:
            fact = {
                "id": str(uuid4()),
                "creator_id": user["user_id"],
                "title": name,
                "brand_name": brand_name.strip(),
                "content": content,
                "description": f"Extracted from {name}",
                "source_url": "",
                "verified": False,
                "enabled": True,
                "asset_id": asset_id,
                "created_at": asset["created_at"],
            }
            facts = read_json(config.DATA_DIR / "library_facts.json", [])
            facts.append(fact)
            write_json(config.DATA_DIR / "library_facts.json", facts)
    return {
        "id": asset_id,
        "name": name,
        "bytes": len(raw),
        "extracted_text": content,
        "fact": fact,
        "extraction_limit": 100000,
        "message": "Uploaded. Extracted source text is unverified until a reviewer verifies it.",
    }


def load_asset(asset_id, user, authorization):
    asset = next(
        (
            r
            for r in read_json(config.DATA_DIR / "assets.json", [])
            if r["id"] == asset_id
        ),
        None,
    )
    if asset is None:
        raise HTTPException(404, "File not found")
    if not can_read(asset, user):
        raise HTTPException(403, "File access denied")
    if config.AUTH_PROVIDER == "supabase":
        raw = storage_request(
            "GET", asset["storage_key"], authorization.split(" ", 1)[1]
        )
    else:
        root = (config.DATA_DIR / "uploads").resolve()
        path = (root / asset["storage_key"]).resolve()
        if root not in path.parents or not path.is_file():
            raise HTTPException(404, "Stored file is missing")
        raw = path.read_bytes()
    return asset, raw


@router.get("/{asset_id}")
def preview(asset_id: str, user=Depends(get_user), authorization: str = Header()):
    asset, raw = load_asset(asset_id, user, authorization)
    content, _ = extract(asset["name"], raw)
    return {
        "id": asset["id"],
        "name": asset["name"],
        "bytes": asset["bytes"],
        "extracted_text": content,
        "extraction_limit": 100000,
    }


@router.get("/{asset_id}/download")
def download(asset_id: str, user=Depends(get_user), authorization: str = Header()):
    asset, raw = load_asset(asset_id, user, authorization)
    return Response(
        raw,
        media_type=asset["content_type"],
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(asset['name'])}"
        },
    )
