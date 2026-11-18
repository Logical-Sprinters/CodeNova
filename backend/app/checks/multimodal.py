"""Bounded OCR and visual-brand checks for uploaded marketing images."""

import hashlib
import io
import math
import os
from pathlib import Path

import cv2
import numpy as np
import pytesseract
from PIL import Image, ImageOps, UnidentifiedImageError
from pytesseract import Output

from app import config

MAX_IMAGE_PIXELS = 20_000_000
Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
COLOR_DISTANCE_TOLERANCE = 45
LOGO_MATCH_THRESHOLD = 0.83
if config.TESSERACT_CMD:
    pytesseract.pytesseract.tesseract_cmd = config.TESSERACT_CMD
elif os.name == "nt":
    default_tesseract = (
        Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
        / "Tesseract-OCR"
        / "tesseract.exe"
    )
    if default_tesseract.is_file():
        pytesseract.pytesseract.tesseract_cmd = str(default_tesseract)


def decode_image(raw: bytes) -> Image.Image:
    try:
        with Image.open(io.BytesIO(raw)) as opened:
            if opened.format not in {"JPEG", "PNG", "WEBP"}:
                raise ValueError("Use a JPEG, PNG or WebP image.")
            if opened.width * opened.height > MAX_IMAGE_PIXELS:
                raise ValueError("Image dimensions must not exceed 20 megapixels.")
            opened.verify()
        with Image.open(io.BytesIO(raw)) as opened:
            oriented = ImageOps.exif_transpose(opened)
            if "A" in oriented.getbands() or "transparency" in oriented.info:
                foreground = oriented.convert("RGBA")
                background = Image.new("RGBA", foreground.size, "white")
                return Image.alpha_composite(background, foreground).convert("RGB")
            return oriented.convert("RGB")
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as error:
        raise ValueError("The uploaded file is not a valid supported image.") from error


def extract_ocr(image: Image.Image) -> dict:
    try:
        data = pytesseract.image_to_data(
            image, output_type=Output.DICT, timeout=15
        )
    except pytesseract.pytesseract.TesseractNotFoundError:
        return {
            "status": "unavailable",
            "reason": "Install the Tesseract OCR executable on the API server.",
            "text": "",
            "blocks": [],
        }
    except RuntimeError as error:
        if "timeout" in str(error).lower():
            return {
                "status": "unavailable",
                "reason": "OCR exceeded its 15-second processing limit.",
                "text": "",
                "blocks": [],
            }
        raise

    blocks = []
    for index, value in enumerate(data["text"]):
        text = value.strip()
        try:
            confidence = float(data["conf"][index])
        except (ValueError, TypeError):
            continue
        if not text or confidence < 0:
            continue
        blocks.append(
            {
                "text": text[:300],
                "confidence": round(confidence / 100, 3),
                "x": int(data["left"][index]),
                "y": int(data["top"][index]),
                "width": int(data["width"][index]),
                "height": int(data["height"][index]),
            }
        )
        if len(blocks) == 500:
            break
    text = " ".join(block["text"] for block in blocks)[:100_000]
    return {"status": "complete", "text": text, "blocks": blocks}


def parse_hex_color(value: str) -> tuple[str, tuple[int, int, int]]:
    normalized = value.strip().upper()
    if len(normalized) == 7 and normalized.startswith("#"):
        normalized = normalized[1:]
    if len(normalized) != 6:
        raise ValueError(f"Invalid palette color: {value!r}")
    try:
        rgb = tuple(int(normalized[index : index + 2], 16) for index in (0, 2, 4))
    except ValueError as error:
        raise ValueError(f"Invalid palette color: {value!r}") from error
    return f"#{normalized}", rgb


def analyze_colors(image: Image.Image, approved_colors: list[str]) -> dict:
    palette = [parse_hex_color(color) for color in approved_colors]
    sample = image.copy()
    sample.thumbnail((256, 256))
    quantized = sample.quantize(colors=8, method=Image.Quantize.MEDIANCUT)
    colors = quantized.getpalette()
    total = max(1, sample.width * sample.height)
    detected = []
    violations = []
    for count, index in quantized.getcolors(256) or []:
        rgb = tuple(colors[(index * 3) : (index * 3 + 3)])
        hex_color = "#{:02X}{:02X}{:02X}".format(*rgb)
        share = count / total
        nearest = None
        distance = None
        if palette:
            nearest, target = min(
                palette,
                key=lambda entry: math.sqrt(
                    sum((a - b) ** 2 for a, b in zip(rgb, entry[1]))
                ),
            )
            distance = round(
                math.sqrt(sum((a - b) ** 2 for a, b in zip(rgb, target))), 1
            )
        approved = bool(
            palette and distance is not None and distance <= COLOR_DISTANCE_TOLERANCE
        )
        detected.append(
            {
                "hex": hex_color,
                "share": round(share, 3),
                "approved": approved if palette else None,
                "nearest_approved": nearest,
                "distance": distance,
            }
        )
        if palette and not approved and share >= 0.02:
            violations.append(
                {
                    "rule_id": "VIS-02",
                    "severity": "review",
                    "message": f"Dominant color {hex_color} is outside the approved palette.",
                    "evidence": f"{hex_color} covers approximately {round(share * 100)}% of the image.",
                    "suggestion": (
                        f"Use an approved color such as {nearest}."
                        if nearest
                        else "Add the approved brand palette before checking colors."
                    ),
                }
            )
    return {
        "status": "complete" if palette else "not_configured",
        "approved_palette": [entry[0] for entry in palette],
        "dominant_colors": sorted(detected, key=lambda item: item["share"], reverse=True),
        "violations": violations,
        "tolerance": COLOR_DISTANCE_TOLERANCE,
    }


def _rgb_image(raw: bytes) -> Image.Image:
    image = decode_image(raw)
    if image.width < 16 or image.height < 16:
        raise ValueError("Logo reference images must be at least 16 by 16 pixels.")
    return image


def match_logo(image: Image.Image, reference_raw: bytes) -> dict:
    reference = _rgb_image(reference_raw)
    source = image.copy()
    source.thumbnail((1600, 1600))
    target_gray = cv2.cvtColor(np.asarray(source), cv2.COLOR_RGB2GRAY)
    template_image = reference.copy()
    template_image.thumbnail((600, 600))
    template = cv2.cvtColor(np.asarray(template_image), cv2.COLOR_RGB2GRAY)
    if float(template.std()) < 2:
        return {"confidence": 0.0, "box": None}
    best = {"confidence": 0.0, "box": None}
    largest_scale = min(
        target_gray.shape[1] / template.shape[1],
        target_gray.shape[0] / template.shape[0],
        2.0,
    )
    scales = [0.2, 0.28, 0.4, 0.56, 0.8, 1.0, 1.25, 1.6, largest_scale]
    for scale in sorted({value for value in scales if 0.05 <= value <= largest_scale}):
        width = round(template.shape[1] * scale)
        height = round(template.shape[0] * scale)
        if width < 16 or height < 16:
            continue
        resized = cv2.resize(template, (width, height), interpolation=cv2.INTER_AREA)
        result = cv2.matchTemplate(target_gray, resized, cv2.TM_CCOEFF_NORMED)
        _, confidence, _, location = cv2.minMaxLoc(result)
        if confidence > best["confidence"]:
            scale_x = image.width / source.width
            scale_y = image.height / source.height
            best = {
                "confidence": round(float(confidence), 3),
                "box": {
                    "x": round(location[0] * scale_x),
                    "y": round(location[1] * scale_y),
                    "width": round(width * scale_x),
                    "height": round(height * scale_y),
                },
            }
    return best


def analyze_logos(
    image: Image.Image,
    approved_logo: bytes | None,
    deprecated_logo: bytes | None,
) -> dict:
    if approved_logo is None and deprecated_logo is None:
        return {
            "status": "not_configured",
            "message": "Provide approved and/or deprecated logo reference images to verify logos.",
            "violations": [],
        }
    approved = match_logo(image, approved_logo) if approved_logo else None
    deprecated = match_logo(image, deprecated_logo) if deprecated_logo else None
    violations = []
    if deprecated and deprecated["confidence"] >= LOGO_MATCH_THRESHOLD:
        status = "deprecated_detected"
        violations.append(
            {
                "rule_id": "VIS-05",
                "severity": "high",
                "message": "A deprecated logo reference was detected.",
                "evidence": f"Logo match confidence: {deprecated['confidence']:.0%}.",
                "suggestion": "Replace it with the current approved logo.",
                "location": deprecated["box"],
            }
        )
    elif approved and approved["confidence"] >= LOGO_MATCH_THRESHOLD:
        status = "approved_detected"
    else:
        status = "not_detected"
    return {
        "status": status,
        "threshold": LOGO_MATCH_THRESHOLD,
        "approved_match": approved,
        "deprecated_match": deprecated,
        "violations": violations,
    }


def analyze_image(
    raw: bytes,
    approved_colors: list[str],
    approved_logo: bytes | None = None,
    deprecated_logo: bytes | None = None,
) -> dict:
    image = decode_image(raw)
    ocr = extract_ocr(image)
    colors = analyze_colors(image, approved_colors)
    logos = analyze_logos(image, approved_logo, deprecated_logo)
    complete = (
        ocr["status"] == "complete"
        and colors["status"] == "complete"
        and logos["status"] in {"approved_detected", "deprecated_detected"}
    )
    return {
        "image_sha256": hashlib.sha256(raw).hexdigest(),
        "image_width": image.width,
        "image_height": image.height,
        "status": "complete" if complete else "partial",
        "ocr": ocr,
        "colors": colors,
        "logo": logos,
        "violations": colors["violations"] + logos["violations"],
    }
