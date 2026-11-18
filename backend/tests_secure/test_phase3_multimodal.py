"""Phase 3 verification tests: Image OCR + copy fusion, VIS-02 palette, VIS-05 logo hash, composite seal."""

import io

import pytest
from PIL import Image, ImageDraw, ImageFont

from app.checks.visual import inspector


def _png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _jpeg_bytes(img: Image.Image, quality: int = 90) -> bytes:
    buf = io.BytesIO()
    img.convert("RGB").save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def _make_legacy_logo() -> Image.Image:
    logo = Image.new("RGBA", (80, 80), (0, 0, 0, 0))
    draw = ImageDraw.Draw(logo)
    draw.ellipse((6, 6, 74, 74), fill="#E11D48", outline="#FACC15", width=4)
    draw.polygon([(20, 52), (40, 18), (60, 52)], fill="#FFFFFF")
    return logo


def _make_approved_logo() -> Image.Image:
    logo = Image.new("RGBA", (80, 80), (0, 0, 0, 0))
    draw = ImageDraw.Draw(logo)
    draw.rounded_rectangle((8, 8, 72, 72), radius=14, fill="#22A895")
    draw.line((16, 60, 64, 20), fill="#FFFFFF", width=8)
    return logo


def _upload_image(client, headers, filename: str, raw: bytes, mime: str = "image/png"):
    res = client.post(
        "/api/v1/files",
        headers=headers,
        files={"file": (filename, raw, mime)},
    )
    assert res.status_code == 201, res.text
    return res.json()


def _other_creator(client):
    res = client.post(
        "/api/v1/auth/signup",
        json={
            "name": "Second Creator",
            "email": "second.creator@example.com",
            "password": "Password123!",
        },
    )
    assert res.status_code == 200, res.text
    return {"Authorization": "Bearer " + res.json()["access_token"]}


def test_image_upload_metadata_preview_and_validation(client, headers):
    creator = headers["creator"]
    other = _other_creator(client)

    img = Image.new("RGB", (400, 200), "#0F172A")
    ImageDraw.Draw(img).rectangle((20, 20, 100, 100), fill="#22A895")
    raw = _png_bytes(img)

    uploaded = _upload_image(client, creator, "approved_flyer.png", raw)
    assert uploaded["is_image"] is True
    assert uploaded["width"] == 400
    assert uploaded["height"] == 200
    assert uploaded["dominant_colors"][0]["hex"] == "#0F172A"
    assert uploaded["file_sha256"]

    preview = client.get(f"/api/v1/files/{uploaded['id']}", headers=creator)
    assert preview.status_code == 200
    assert preview.json()["is_image"] is True
    assert preview.json()["dominant_colors"][0]["hex"] == "#0F172A"

    dl_inline = client.get(
        f"/api/v1/files/{uploaded['id']}/download?inline=true", headers=creator
    )
    assert dl_inline.status_code == 200
    assert dl_inline.content == raw
    assert "inline;" in dl_inline.headers["content-disposition"]

    # Cross-creator asset read/attach isolation
    assert client.get(f"/api/v1/files/{uploaded['id']}", headers=other).status_code == 403
    assert (
        client.post(
            "/api/v1/brand/check",
            headers=other,
            json={
                "brand_name": "Acme",
                "content": "Factual caption.",
                "content_type": "multimodal",
                "asset_ids": [uploaded["id"]],
            },
        ).status_code
        == 403
    )

    # Corrupt image rejected with 422
    bad = client.post(
        "/api/v1/files",
        headers=creator,
        files={"file": ("broken.png", b"not-a-valid-png", "image/png")},
    )
    assert bad.status_code == 422


def test_multimodal_ocr_graceful_fallback_without_tesseract(client, headers, monkeypatch):
    monkeypatch.setattr(inspector, "_resolve_tesseract_cmd", lambda: None)
    creator = headers["creator"]

    # Unapproved #1E40AF cobalt background + text
    banner = Image.new("RGB", (600, 300), "#1E40AF")
    ImageDraw.Draw(banner).text(
        (40, 120), "Guaranteed 18% returns", fill="#FFFFFF", font=ImageFont.load_default(size=32)
    )
    asset = _upload_image(client, creator, "cobalt.png", _png_bytes(banner))
    assert asset["ocr_status"] == "tesseract_not_installed"
    assert asset["extracted_text"] == ""
    assert asset["dominant_colors"][0]["hex"] == "#1E40AF"

    # Palette VIS-02 still catches #1E40AF even when Tesseract is absent!
    check = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Factual savings guide.",
            "content_type": "multimodal",
            "asset_ids": [asset["id"]],
        },
    )
    assert check.status_code == 200, check.text
    body = check.json()
    assert body["visual_summary"][0]["ocr_status"] == "tesseract_not_installed"
    vis02 = [f for f in body["findings"] if f["rule_id"] == "VIS-02"]
    assert len(vis02) == 1
    assert vis02[0]["source_origin"] == "visual"
    assert vis02[0]["visual_evidence"]["detected_hex"] == "#1E40AF"


def test_multimodal_visual_palette_logo_preflight_and_composite_seal(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]

    # 1. Reviewer registers deprecated 2024 logo template on VIS-05
    legacy_logo = _make_legacy_logo()
    tmpl_res = client.post(
        "/api/v1/library/rules/VIS-05/logo-template?brand_name=Acme&label=Legacy+2024+Crest",
        headers=reviewer,
        files={"file": ("legacy_logo.png", _png_bytes(legacy_logo), "image/png")},
    )
    assert tmpl_res.status_code == 201 or tmpl_res.status_code == 200, tmpl_res.text
    assert tmpl_res.json()["rule_id"] == "VIS-05"
    assert tmpl_res.json()["total_templates"] == 1

    # 2. Bad banner: unapproved #1E40AF background + resized deprecated logo in top-left corner (JPEG)
    bad_banner = Image.new("RGB", (800, 400), "#1E40AF")
    bad_banner.paste(legacy_logo.resize((68, 68)), (22, 22), legacy_logo.resize((68, 68)))
    bad_asset = _upload_image(
        client, creator, "bad_flyer.jpg", _jpeg_bytes(bad_banner), mime="image/jpeg"
    )

    # Stateless preflight detects VIS-02 + VIS-05 without creating review records
    pre = client.post(
        "/api/v1/brand/preflight",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Explore Acme banking features.",
            "asset_ids": [bad_asset["id"]],
        },
    )
    assert pre.status_code == 200, pre.text
    pre_rules = {f["rule_id"] for f in pre.json()["findings"]}
    assert {"VIS-02", "VIS-05"}.issubset(pre_rules)
    assert client.get("/api/v1/reviews", headers=creator).json()["total"] == 0

    # Full multimodal check persists findings & survives reviewer re-verification
    bad_check = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Explore Acme banking features.",
            "content_type": "multimodal",
            "asset_ids": [bad_asset["id"]],
        },
    )
    assert bad_check.status_code == 200, bad_check.text
    bad_ids = {f["rule_id"] for f in bad_check.json()["findings"]}
    assert {"VIS-02", "VIS-05"}.issubset(bad_ids)
    assert bad_check.json()["dropped_ungrounded_count"] == 0

    queue = client.get("/api/v1/reviews?status=pending", headers=reviewer).json()
    matched_q = next(r for r in queue["reviews"] if r["check_id"] == bad_check.json()["check_id"])
    assert {"VIS-02", "VIS-05"}.issubset({f["rule_id"] for f in matched_q["findings"]})

    # 3. Clean banner: approved #0F172A background + new approved logo -> passes visual checks!
    clean_banner = Image.new("RGB", (800, 400), "#0F172A")
    new_logo = _make_approved_logo()
    clean_banner.paste(new_logo.resize((68, 68)), (22, 22), new_logo.resize((68, 68)))
    clean_raw = _png_bytes(clean_banner)
    clean_asset = _upload_image(client, creator, "clean_flyer.png", clean_raw)

    v2 = client.post(
        f"/api/v1/brand/{bad_check.json()['check_id']}/versions",
        headers=creator,
        json={
            "content": "Explore Acme banking features.",
            "expected_version": 1,
            "asset_ids": [clean_asset["id"]],
        },
    )
    assert v2.status_code == 200, v2.text
    assert v2.json()["total_findings"] == 0
    assert v2.json()["scan_status"] == "passed"

    # Reviewer approves v2 -> composite text + image SHA-256 seal created
    approved = client.patch(
        f"/api/v1/reviews/{bad_check.json()['check_id']}/decision",
        headers=reviewer,
        json={"decision": "approved", "expected_version": 2, "note": "Clean multimodal asset"},
    )
    assert approved.status_code == 200, approved.text
    cid = bad_check.json()["check_id"]

    # Exact text + exact image -> SEALED
    verify_ok = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={
            "check_id": cid,
            "brand_name": "Acme",
            "content": "Explore Acme banking features.",
            "asset_ids": [clean_asset["id"]],
        },
    )
    assert verify_ok.status_code == 200
    assert verify_ok.json()["valid"] is True
    assert verify_ok.json()["seal_status"] == "SEALED"

    # Missing asset_ids on a multimodal seal -> VOIDED_TAMPERED
    verify_missing = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={
            "check_id": cid,
            "brand_name": "Acme",
            "content": "Explore Acme banking features.",
        },
    )
    assert verify_missing.status_code == 200
    assert verify_missing.json()["valid"] is False
    assert verify_missing.json()["seal_status"] == "VOIDED_TAMPERED"
    assert verify_missing.json()["asset_tampered"] is True

    # Single-pixel tampered image -> VOIDED_TAMPERED via both /verify and /verify-upload!
    tampered_banner = clean_banner.copy()
    tampered_banner.putpixel((400, 200), (16, 24, 43))
    tampered_raw = _png_bytes(tampered_banner)
    tampered_asset = _upload_image(client, creator, "tampered_flyer.png", tampered_raw)

    verify_tampered = client.post(
        "/api/v1/approvals/verify",
        headers=creator,
        json={
            "check_id": cid,
            "brand_name": "Acme",
            "content": "Explore Acme banking features.",
            "asset_ids": [tampered_asset["id"]],
        },
    )
    assert verify_tampered.status_code == 200
    assert verify_tampered.json()["valid"] is False
    assert verify_tampered.json()["seal_status"] == "VOIDED_TAMPERED"
    assert verify_tampered.json()["asset_tampered"] is True

    verify_upload_bad = client.post(
        "/api/v1/approvals/verify-upload",
        headers=creator,
        data={
            "check_id": cid,
            "brand_name": "Acme",
            "content": "Explore Acme banking features.",
        },
        files={"file": ("tampered_flyer.png", tampered_raw, "image/png")},
    )
    assert verify_upload_bad.status_code == 200
    assert verify_upload_bad.json()["valid"] is False
    assert verify_upload_bad.json()["seal_status"] == "VOIDED_TAMPERED"


@pytest.mark.skipif(
    inspector._resolve_tesseract_cmd() is None,
    reason="Tesseract OCR binary not installed on host",
)
def test_multimodal_real_tesseract_ocr_caption_and_fact_fusion(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]

    # Verified fact: Acme Savings rate is 4.5%
    fact = client.post(
        "/api/v1/library/facts",
        headers=reviewer,
        json={
            "title": "Acme Savings Rate 2026",
            "brand_name": "Acme",
            "content": "Acme Savings accounts currently earn 4.5% APY for eligible customers.",
            "verified": True,
            "enabled": True,
        },
    )
    assert fact.status_code == 201, fact.text

    # Register deprecated logo on VIS-05
    legacy_logo = _make_legacy_logo()
    client.post(
        "/api/v1/library/rules/VIS-05/logo-template?brand_name=Acme&label=Legacy+2024+Crest",
        headers=reviewer,
        files={"file": ("legacy.png", _png_bytes(legacy_logo), "image/png")},
    )

    # Banner with #1E40AF cobalt bg + deprecated logo + text "Guaranteed 18% returns"
    banner = Image.new("RGB", (1000, 420), "#1E40AF")
    banner.paste(legacy_logo.resize((74, 74)), (24, 24), legacy_logo.resize((74, 74)))
    draw = ImageDraw.Draw(banner)
    draw.text(
        (130, 170),
        "Guaranteed 18% returns\nAcme Savings APY",
        fill="#FFFFFF",
        font=ImageFont.load_default(size=44),
    )
    asset = _upload_image(client, creator, "promo_banner.png", _png_bytes(banner))
    assert asset["ocr_status"] == "completed"
    assert "Guaranteed 18% returns" in asset["extracted_text"]

    # Preflight catches OCR fact contradiction (18% vs 4.5%), COMP-14/BG-002, VIS-02, VIS-05!
    pre = client.post(
        "/api/v1/brand/preflight",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Grow your savings with Acme this season.",
            "asset_ids": [asset["id"]],
        },
    )
    assert pre.status_code == 200, pre.text
    pre_data = pre.json()
    assert "Guaranteed 18% returns" in pre_data["ocr_text"]
    pre_by_rule = {f["rule_id"]: f for f in pre_data["findings"]}
    assert "COMP-14" in pre_by_rule
    assert pre_by_rule["COMP-14"]["source_origin"] == "image_ocr"
    assert "VIS-02" in pre_by_rule
    assert "VIS-05" in pre_by_rule
    assert any(
        f["rule_id"].startswith("AI-FACT-") and f["source_origin"] == "image_ocr"
        for f in pre_data["findings"]
    )

    # Full multimodal check creates grounded findings across caption/OCR/visual & preserves in review queue
    full = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Grow your savings with Acme this season.",
            "content_type": "multimodal",
            "asset_ids": [asset["id"]],
        },
    )
    assert full.status_code == 200, full.text
    full_data = full.json()
    assert full_data["dropped_ungrounded_count"] == 0
    full_rules = {f["rule_id"] for f in full_data["findings"]}
    assert {"COMP-14", "BG-002", "VIS-02", "VIS-05"}.issubset(full_rules)

    # Reviewer queue re-verification retains image_ocr & visual findings!
    rev_queue = client.get("/api/v1/reviews?status=pending", headers=reviewer).json()
    rec = next(r for r in rev_queue["reviews"] if r["check_id"] == full_data["check_id"])
    assert {"COMP-14", "BG-002", "VIS-02", "VIS-05"}.issubset(
        {f["rule_id"] for f in rec["findings"]}
    )
    assert any(f["source_origin"] == "image_ocr" for f in rec["findings"])
    assert any(f["source_origin"] == "visual" for f in rec["findings"])


@pytest.mark.skipif(
    inspector._resolve_tesseract_cmd() is None,
    reason="Tesseract OCR binary not installed on host",
)
def test_multimodal_ocr_conflict_gate_and_auto_recheck(client, headers):
    creator, reviewer = headers["creator"], headers["reviewer"]

    # Create conflicting topic_key rule + fact on refund_window
    r_res = client.post(
        "/api/v1/library/rules",
        headers=reviewer,
        json={
            "rule_id": "ACME-REFUND-OCR",
            "title": "7-Day Refund Rule",
            "brand_name": "Acme",
            "pattern": r"\brefund\b",
            "description": "Refunds allowed within 7 days.",
            "rule_text": "All Acme refunds are limited to 7 days from purchase.",
            "topic_key": "refund_window",
            "canonical_value": "7 days",
            "topic_keywords": ["refund", "refunds"],
            "severity": "review",
        },
    )
    assert r_res.status_code == 201, r_res.text

    f_res = client.post(
        "/api/v1/library/facts",
        headers=reviewer,
        json={
            "title": "30-Day Refund Fact",
            "brand_name": "Acme",
            "content": "Customers receive a 30 days full refund guarantee.",
            "topic_key": "refund_window",
            "canonical_value": "30 days",
            "topic_keywords": ["refund", "refunds"],
            "verified": True,
            "enabled": True,
        },
    )
    assert f_res.status_code == 201, f_res.text

    # Clean caption, conflicting keyword "refund" appears inside uploaded image OCR + #1E40AF palette
    banner = Image.new("RGB", (900, 320), "#1E40AF")
    ImageDraw.Draw(banner).text(
        (50, 110), "Easy refund policy", fill="#FFFFFF", font=ImageFont.load_default(size=44)
    )
    asset = _upload_image(client, creator, "refund_banner.png", _png_bytes(banner))
    assert "refund" in asset["extracted_text"].lower()

    chk = client.post(
        "/api/v1/brand/check",
        headers=creator,
        json={
            "brand_name": "Acme",
            "content": "Learn more about Acme customer care.",
            "content_type": "multimodal",
            "asset_ids": [asset["id"]],
        },
    )
    assert chk.status_code == 200, chk.text
    chk_data = chk.json()
    assert chk_data["status"] == "review_paused_conflict"
    assert chk_data["scan_status"] == "abstained_conflict"
    assert chk_data["conflict_id"]

    # Resolving the conflict auto-rechecks WITH the attached asset preserved!
    resolved = client.post(
        f"/api/v1/conflicts/{chk_data['conflict_id']}/resolve",
        headers=reviewer,
        json={
            "winning_source_type": "rule",
            "winning_source_id": "ACME-REFUND-OCR",
            "resolution_note": "7-day rule wins",
            "auto_recheck": True,
        },
    )
    assert resolved.status_code == 200, resolved.text
    updated = resolved.json()["updated_checks"][0]
    assert updated["status"] == "pending"

    reviews = client.get("/api/v1/reviews?status=pending", headers=reviewer).json()
    rec = next(r for r in reviews["reviews"] if r["check_id"] == chk_data["check_id"])
    assert {"ACME-REFUND-OCR", "VIS-02"}.issubset({f["rule_id"] for f in rec["findings"]})

