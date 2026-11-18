import io
import json

from PIL import Image, ImageDraw

from app.checks.multimodal import analyze_colors, match_logo
from app.receipts import store as receipt_store


def image_bytes(color):
    image = Image.new("RGB", (80, 60), color)
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def test_color_analysis_compares_dominant_color_with_palette():
    image = Image.open(io.BytesIO(image_bytes((255, 0, 0)))).convert("RGB")

    approved = analyze_colors(image, ["#FF0000", "#FFFFFF"])
    rejected = analyze_colors(image, ["#0000FF"])
    skipped = analyze_colors(image, [])

    assert approved["status"] == "complete"
    assert approved["violations"] == []
    assert rejected["violations"][0]["rule_id"] == "VIS-02"
    assert rejected["dominant_colors"][0]["hex"] == "#FF0000"
    assert skipped["status"] == "not_configured"
    assert skipped["violations"] == []


def test_logo_matching_returns_confident_reference_location():
    reference = Image.new("RGB", (50, 40), "white")
    draw = ImageDraw.Draw(reference)
    draw.rectangle((4, 5, 20, 34), fill="#102030")
    draw.ellipse((25, 8, 45, 28), fill="#E04080")
    draw.line((2, 37, 48, 2), fill="#20B080", width=3)
    source = Image.new("RGB", (300, 200), "white")
    source.paste(reference, (120, 70))
    reference_bytes = io.BytesIO()
    reference.save(reference_bytes, format="PNG")

    match = match_logo(source, reference_bytes.getvalue())

    assert match["confidence"] >= 0.83
    assert 115 <= match["box"]["x"] <= 125
    assert 65 <= match["box"]["y"] <= 75


def test_multimodal_check_combines_ocr_and_caption_and_receipts_visual_evidence(
    client, creator_headers, monkeypatch
):
    from app.routers import brand

    monkeypatch.setattr(
        brand,
        "analyze_image",
        lambda *args, **kwargs: {
            "image_sha256": "a" * 64,
            "image_width": 80,
            "image_height": 60,
            "ocr": {
                "status": "complete",
                "text": "Guaranteed 12% returns",
                "blocks": [{"text": "Guaranteed", "x": 4, "y": 5}],
            },
            "colors": {"status": "complete", "dominant_colors": [], "violations": []},
            "logo": {"status": "not_configured", "violations": []},
            "violations": [
                {
                    "rule_id": "VIS-02",
                    "severity": "review",
                    "message": "Unapproved color detected.",
                    "evidence": "#FF0000 covers 80% of the image.",
                    "suggestion": "Use an approved color.",
                }
            ],
        },
    )

    response = client.post(
        "/api/v1/brand/multimodal-check",
        data={
            "brand_name": "Acme",
            "caption": "Invest today",
            "approved_colors": json.dumps(["#0F172A"]),
        },
        files={"image": ("ad.png", image_bytes((255, 0, 0)), "image/png")},
        headers=creator_headers,
    )

    assert response.status_code == 200, response.text
    result = response.json()
    assert result["checked_content"] == "Invest today\n\nGuaranteed 12% returns"
    assert result["total_findings"] == len(result["findings"]) + 1
    assert result["scan_status"] == "findings_detected"
    assert result["visual_analysis"]["image_sha256"] == "a" * 64
    receipt = receipt_store.get_receipt(result["receipt_id"])
    assert receipt["visual_analysis"]["image_sha256"] == "a" * 64


def test_multimodal_check_rejects_empty_caption_when_ocr_is_unavailable(
    client, creator_headers, monkeypatch
):
    from app.routers import brand
    from app.approval import store as approval_store

    monkeypatch.setattr(
        brand,
        "analyze_image",
        lambda *args, **kwargs: {
            "image_sha256": "b" * 64,
            "image_width": 80,
            "image_height": 60,
            "ocr": {
                "status": "unavailable",
                "reason": "Install Tesseract on the API server.",
                "text": "",
                "blocks": [],
            },
            "colors": {"status": "not_configured", "violations": []},
            "logo": {"status": "not_configured", "violations": []},
            "violations": [],
        },
    )

    response = client.post(
        "/api/v1/brand/multimodal-check",
        data={"brand_name": "Acme", "caption": "", "approved_colors": "[]"},
        files={"image": ("ad.png", image_bytes((0, 0, 0)), "image/png")},
        headers=creator_headers,
    )

    assert response.status_code == 503
    assert "Tesseract" in response.json()["detail"]
    assert approval_store.load_records() == []
