"""Private TXT/Markdown/PDF and multimodal image storage, OCR, and visual inspection."""

from datetime import datetime, timezone
import hashlib
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
from app.checks.visual.inspector import extract_image_metadata
from app.storage import STORE_LOCK, read_json, write_json

router = APIRouter(prefix="/api/v1/files", tags=["Private document storage"])
MAX_BYTES = 5 * 1024 * 1024
IMAGE_SUFFIXES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
}


def extract(filename, raw):
    suffix = Path(filename).suffix.lower()
    try:
        if suffix in {".txt", ".md"}:
            text = raw.decode("utf-8-sig")[:100000]
            if not text.strip():
                raise HTTPException(422, "The document has no readable text")
            return {
                "extracted_text": text,
                "mime": "text/plain; charset=utf-8",
                "is_image": False,
                "file_sha256": hashlib.sha256(raw).hexdigest(),
                "width": None,
                "height": None,
                "dominant_colors": [],
                "ocr_status": "not_applicable",
                "ocr_words": [],
            }
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
                    "No text was extracted. Scanned/image PDFs need PDF-to-image OCR, which is not configured.",
                )
            return {
                "extracted_text": text,
                "mime": "application/pdf",
                "is_image": False,
                "file_sha256": hashlib.sha256(raw).hexdigest(),
                "width": None,
                "height": None,
                "dominant_colors": [],
                "ocr_status": "not_applicable",
                "ocr_words": [],
            }
        if suffix in IMAGE_SUFFIXES:
            meta = extract_image_metadata(raw)
            return {
                "extracted_text": meta["extracted_text"],
                "mime": IMAGE_SUFFIXES[suffix],
                "is_image": True,
                "file_sha256": meta["file_sha256"],
                "width": meta["width"],
                "height": meta["height"],
                "dominant_colors": meta["dominant_colors"],
                "ocr_status": meta["ocr_status"],
                "ocr_words": meta["ocr_words"],
            }
    except HTTPException:
        raise
    except ValueError as error:
        raise HTTPException(422, str(error)) from error
    except Exception as error:
        raise HTTPException(
            422, "Cannot extract readable UTF-8/PDF/image data from this file"
        ) from error
    raise HTTPException(
        415,
        "Supported uploads: .txt, .md, text-based .pdf, and images (.png, .jpg, .jpeg, .webp).",
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
    authorization: str = Header(default=""),
):
    if as_fact:
        require_reviewer(user)
    raw = await file.read(MAX_BYTES + 1)
    if not raw or len(raw) > MAX_BYTES:
        raise HTTPException(413, "Upload a nonempty document no larger than 5 MB")
    name = Path((file.filename or "document.txt").replace("\\", "/")).name[:160]
    info = extract(name, raw)
    content = info["extracted_text"]
    mime = info["mime"]
    if as_fact and not content.strip():
        raise HTTPException(
            422,
            "Cannot ingest as a factual source because no readable text/OCR text was extracted.",
        )

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
            "file_sha256": info["file_sha256"],
            "is_image": info["is_image"],
            "width": info["width"],
            "height": info["height"],
            "dominant_colors": info["dominant_colors"],
            "ocr_status": info["ocr_status"],
            "extracted_text": content,
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
        "content_type": mime,
        "file_sha256": info["file_sha256"],
        "is_image": info["is_image"],
        "width": info["width"],
        "height": info["height"],
        "dominant_colors": info["dominant_colors"],
        "ocr_status": info["ocr_status"],
        "ocr_words": info["ocr_words"],
        "extracted_text": content,
        "fact": fact,
        "extraction_limit": 100000,
        "message": (
            "Image uploaded and inspected (OCR + dominant colors)."
            if info["is_image"]
            else "Uploaded. Extracted source text is unverified until a reviewer verifies it."
        ),
    }


def load_asset(asset_id, user, authorization=""):
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
        token = authorization.split(" ", 1)[1] if " " in authorization else authorization
        raw = storage_request("GET", asset["storage_key"], token)
    else:
        root = (config.DATA_DIR / "uploads").resolve()
        path = (root / asset["storage_key"]).resolve()
        if root not in path.parents or not path.is_file():
            raise HTTPException(404, "Stored file is missing")
        raw = path.read_bytes()
    return asset, raw


@router.get("/{asset_id}")
def preview(asset_id: str, user=Depends(get_user), authorization: str = Header(default="")):
    asset, raw = load_asset(asset_id, user, authorization)
    info = extract(asset["name"], raw)
    return {
        "id": asset["id"],
        "name": asset["name"],
        "bytes": asset["bytes"],
        "content_type": info["mime"],
        "file_sha256": info["file_sha256"],
        "is_image": info["is_image"],
        "width": info["width"],
        "height": info["height"],
        "dominant_colors": info["dominant_colors"],
        "ocr_status": info["ocr_status"],
        "ocr_words": info["ocr_words"],
        "extracted_text": info["extracted_text"],
        "extraction_limit": 100000,
    }


@router.get("/{asset_id}/download")
def download(
    asset_id: str,
    inline: bool = False,
    user=Depends(get_user),
    authorization: str = Header(default=""),
):
    asset, raw = load_asset(asset_id, user, authorization)
    disposition = "inline" if inline else "attachment"
    return Response(
        raw,
        media_type=asset["content_type"],
        headers={
            "Content-Disposition": f"{disposition}; filename*=UTF-8''{quote(asset['name'])}"
        },
    )
