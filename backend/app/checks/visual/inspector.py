"""Multimodal image analysis: OCR extraction, dominant palette check (VIS-02), and logo check (VIS-05)."""

import base64
from collections import Counter
import hashlib
from io import BytesIO
import json
import math
import os
from pathlib import Path
import shutil

import httpx
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps, UnidentifiedImageError
import pytesseract

from app import config
from app.checks.grounding import extract_verbatim_quote


def _resolve_tesseract_cmd() -> str | None:
    if config.TESSERACT_CMD and Path(config.TESSERACT_CMD).is_file():
        return config.TESSERACT_CMD
    found = shutil.which("tesseract")
    if found:
        return found
    for candidate in (
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        "/usr/bin/tesseract",
        "/usr/local/bin/tesseract",
    ):
        if Path(candidate).is_file():
            return candidate
    return None


def _open_rgb_image(raw: bytes) -> tuple[Image.Image, dict]:
    try:
        with Image.open(BytesIO(raw)) as img:
            fmt = (img.format or "PNG").upper()
            width, height = img.size
            if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
                rgba = img.convert("RGBA")
                bg = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
                rgb = Image.alpha_composite(bg, rgba).convert("RGB")
            else:
                rgb = img.convert("RGB")
            return rgb, {"width": width, "height": height, "format": fmt}
    except (UnidentifiedImageError, OSError, ValueError) as error:
        raise ValueError("Invalid or unsupported image bytes") from error


def _rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(int(rgb[0]), int(rgb[1]), int(rgb[2]))


def _hex_to_rgb(hex_str: str) -> tuple[int, int, int] | None:
    cleaned = (hex_str or "").strip().lstrip("#")
    if len(cleaned) != 6:
        return None
    try:
        return (int(cleaned[0:2], 16), int(cleaned[2:4], 16), int(cleaned[4:6], 16))
    except ValueError:
        return None


def _rgb_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def _image_pixels(img: Image.Image) -> list:
    getter = getattr(img, "get_flattened_data", None)
    return list(getter()) if callable(getter) else list(img.getdata())


def extract_dominant_colors(raw: bytes, top_k: int = 6) -> list[dict]:
    rgb, _ = _open_rgb_image(raw)
    thumb = rgb.copy()
    thumb.thumbnail((160, 160), Image.Resampling.NEAREST)
    pixels = _image_pixels(thumb)
    total = max(1, len(pixels))
    exact_counts = Counter(pixels)

    if len(exact_counts) <= 64:
        ranked = exact_counts.most_common(top_k)
        return [
            {
                "hex": _rgb_to_hex(color),
                "rgb": list(color),
                "coverage_pct": round((count / total) * 100.0, 2),
            }
            for color, count in ranked
        ]

    quantized = thumb.quantize(colors=min(12, max(top_k, 8)), method=Image.Quantize.MEDIANCUT)
    palette = quantized.getpalette() or []
    q_counts = Counter(_image_pixels(quantized))
    results = []
    for idx, count in q_counts.most_common(top_k):
        base = idx * 3
        if base + 2 < len(palette):
            c = (palette[base], palette[base + 1], palette[base + 2])
            results.append(
                {
                    "hex": _rgb_to_hex(c),
                    "rgb": list(c),
                    "coverage_pct": round((count / total) * 100.0, 2),
                }
            )
    return results


def _dhash_bits(gray: Image.Image) -> str:
    small = gray.convert("L").resize((9, 8), Image.Resampling.BILINEAR)
    arr = np.asarray(small, dtype=np.int16)
    diff = arr[:, 1:] > arr[:, :-1]
    bits = "".join("1" if val else "0" for val in diff.flatten())
    return f"{int(bits, 2):016x}"


def _trim_foreground(rgb: Image.Image) -> Image.Image:
    """Crop away solid border background padding using corner-median distance."""
    arr = np.asarray(rgb, dtype=np.int16)
    h, w, _ = arr.shape
    if h < 12 or w < 12:
        return rgb
    corners = np.array([arr[0, 0], arr[0, w - 1], arr[h - 1, 0], arr[h - 1, w - 1]])
    bg = np.median(corners, axis=0)
    dist = np.linalg.norm(arr - bg, axis=2)
    ys, xs = np.where(dist > 22.0)
    if len(xs) < 16:
        return rgb
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    if (x1 - x0) < 8 or (y1 - y0) < 8:
        return rgb
    return rgb.crop((x0, y0, x1, y1))


def compute_logo_signature(raw: bytes, label: str = "Deprecated Logo") -> dict:
    rgb, meta = _open_rgb_image(raw)
    fg = _trim_foreground(rgb)
    edges = fg.convert("L").filter(ImageFilter.FIND_EDGES)
    dark_dhash = None
    try:
        with Image.open(BytesIO(raw)) as src:
            if src.mode in ("RGBA", "LA") or (src.mode == "P" and "transparency" in src.info):
                rgba = src.convert("RGBA")
                dark_bg = Image.new("RGBA", rgba.size, (15, 23, 42, 255))
                dark_rgb = Image.alpha_composite(dark_bg, rgba).convert("RGB")
                dark_dhash = _dhash_bits(_trim_foreground(dark_rgb))
    except Exception:
        dark_dhash = None
    return {
        "label": label,
        "dhash": _dhash_bits(fg),
        "dark_dhash": dark_dhash,
        "edge_dhash": _dhash_bits(edges),
        "raw_dhash": _dhash_bits(rgb),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "width": meta["width"],
        "height": meta["height"],
    }


def _hamming_hex(a: str, b: str) -> int:
    try:
        return (int(a, 16) ^ int(b, 16)).bit_count()
    except (ValueError, TypeError):
        return 64


def extract_image_ocr(raw: bytes) -> dict:
    rgb, meta = _open_rgb_image(raw)
    cmd = _resolve_tesseract_cmd()
    if cmd is None:
        return {
            "text": "",
            "words": [],
            "ocr_status": "tesseract_not_installed",
            "width": meta["width"],
            "height": meta["height"],
            "format": meta["format"],
        }
    pytesseract.pytesseract.tesseract_cmd = cmd
    # Upscale small banners & boost contrast for cleaner OCR on colored backgrounds.
    work = rgb
    if min(work.size) < 600:
        scale = 2
        work = work.resize((work.width * scale, work.height * scale), Image.Resampling.BICUBIC)
    gray = ImageOps.autocontrast(work.convert("L"))
    gray = ImageEnhance.Contrast(gray).enhance(1.5)

    # Also test inverted grayscale if dark background banner (common in navy fintech banners).
    candidates = [gray]
    arr = np.asarray(gray)
    if float(arr.mean()) < 115.0:
        candidates.insert(0, ImageOps.invert(gray))

    best_text = ""
    best_words = []
    for candidate in candidates:
        raw_text = pytesseract.image_to_string(candidate, config="--psm 6")
        cleaned = " ".join(raw_text.split())
        if len(cleaned) > len(best_text):
            best_text = cleaned
            try:
                data = pytesseract.image_to_data(
                    candidate,
                    config="--psm 6",
                    output_type=pytesseract.Output.DICT,
                )
                words = []
                for idx, token in enumerate(data.get("text", [])):
                    word = (token or "").strip()
                    if word:
                        words.append(
                            {
                                "text": word,
                                "left": int(data["left"][idx]),
                                "top": int(data["top"][idx]),
                                "width": int(data["width"][idx]),
                                "height": int(data["height"][idx]),
                            }
                        )
                best_words = words
            except Exception:
                best_words = []

    return {
        "text": best_text[:100000],
        "words": best_words[:300],
        "ocr_status": "completed",
        "width": meta["width"],
        "height": meta["height"],
        "format": meta["format"],
    }


def extract_image_metadata(raw: bytes) -> dict:
    ocr = extract_image_ocr(raw)
    colors = extract_dominant_colors(raw)
    return {
        "extracted_text": ocr["text"],
        "ocr_status": ocr["ocr_status"],
        "ocr_words": ocr["words"],
        "dominant_colors": colors,
        "width": ocr["width"],
        "height": ocr["height"],
        "format": ocr["format"],
        "file_sha256": hashlib.sha256(raw).hexdigest(),
    }


def _stable_visual_finding_id(rule_id: str, rule_version: str, asset_id: str, key: str) -> str:
    raw = f"{rule_id}:{rule_version}:visual:{asset_id}:{key}".encode("utf-8")
    return "fnd-" + hashlib.sha256(raw).hexdigest()[:16]


def inspect_palette_rules(
    raw: bytes,
    asset_id: str,
    asset_name: str,
    active_rules: list[dict],
    channel: str = "all",
) -> list[dict]:
    palette_rules = [
        r
        for r in active_rules
        if r.get("enabled", True) and r.get("rule_type") == "visual_palette"
    ]
    if not palette_rules:
        return []
    dominant = extract_dominant_colors(raw, top_k=6)
    findings = []

    for rule in palette_rules:
        allowed_hexes = [h.strip().upper() for h in (rule.get("allowed_hex_colors") or []) if h.strip()]
        banned_hexes = [h.strip().upper() for h in (rule.get("banned_hex_colors") or []) if h.strip()]
        allowed_rgbs = [c for h in allowed_hexes if (c := _hex_to_rgb(h)) is not None]
        banned_rgbs = [(h, _hex_to_rgb(h)) for h in banned_hexes if _hex_to_rgb(h) is not None]

        rule_id = rule["id"]
        rule_version = str(rule.get("version") or "1.0.0")
        rule_text = rule.get("rule_text") or rule.get("message") or ""
        quote, q_start, q_end = extract_verbatim_quote(rule_text, rule.get("rule_quote"))

        for entry in dominant:
            if entry["coverage_pct"] < 12.0:
                continue
            rgb = tuple(entry["rgb"])
            hex_val = entry["hex"]
            banned_hit = any(_rgb_distance(rgb, b_rgb) <= 35.0 for _, b_rgb in banned_rgbs)
            allowed_hit = (
                any(_rgb_distance(rgb, a_rgb) <= 32.0 for a_rgb in allowed_rgbs)
                if allowed_rgbs
                else True
            )
            if banned_hit or not allowed_hit:
                findings.append(
                    {
                        "finding_id": _stable_visual_finding_id(
                            rule_id, rule_version, asset_id, hex_val
                        ),
                        "rule_id": rule_id,
                        "rule_version": rule_version,
                        "rule_quote": quote,
                        "rule_quote_start": q_start,
                        "rule_quote_end": q_end,
                        "severity": rule.get("severity", "review"),
                        "message": f"{rule.get('message', 'Unapproved palette color')} ({hex_val}, {entry['coverage_pct']}% of {asset_name})",
                        "evidence": f"{hex_val} ({entry['coverage_pct']}%)",
                        "start_index": 0,
                        "end_index": 0,
                        "suggestion": rule.get("suggestion"),
                        "replacement": rule.get("replacement"),
                        "source_origin": "visual",
                        "channel": (channel or "all").lower(),
                        "visual_evidence": {
                            "check": "palette",
                            "asset_id": asset_id,
                            "asset_name": asset_name,
                            "detected_hex": hex_val,
                            "coverage_pct": entry["coverage_pct"],
                            "banned_hex_match": banned_hit,
                            "allowed_hex_colors": allowed_hexes,
                        },
                    }
                )
                break  # One grounded palette finding per rule per asset.
    return findings


def _candidate_regions(rgb: Image.Image) -> list[tuple[str, Image.Image]]:
    w, h = rgb.size
    regions = [
        ("full", rgb),
        ("top-left", rgb.crop((0, 0, max(16, int(w * 0.42)), max(16, int(h * 0.45))))),
        ("top-left-corner", rgb.crop((0, 0, max(16, int(w * 0.28)), max(16, int(h * 0.30))))),
        ("top-right", rgb.crop((int(w * 0.58), 0, w, max(16, int(h * 0.45))))),
        ("top-right-corner", rgb.crop((int(w * 0.72), 0, w, max(16, int(h * 0.30))))),
        ("bottom-left", rgb.crop((0, int(h * 0.55), max(16, int(w * 0.42)), h))),
        ("bottom-right", rgb.crop((int(w * 0.58), int(h * 0.55), w, h))),
        ("top-center", rgb.crop((int(w * 0.25), 0, int(w * 0.75), max(16, int(h * 0.40))))),
    ]
    return regions


def inspect_logo_rules(
    raw: bytes,
    asset_id: str,
    asset_name: str,
    active_rules: list[dict],
    channel: str = "all",
) -> list[dict]:
    logo_rules = [
        r
        for r in active_rules
        if r.get("enabled", True) and r.get("rule_type") == "visual_logo"
    ]
    if not logo_rules:
        return []

    rgb, _ = _open_rgb_image(raw)
    asset_sha = hashlib.sha256(raw).hexdigest()
    regions = _candidate_regions(rgb)
    region_hashes = []
    for reg_name, crop in regions:
        fg = _trim_foreground(crop)
        edges = fg.convert("L").filter(ImageFilter.FIND_EDGES)
        region_hashes.append(
            {
                "region": reg_name,
                "raw_dhash": _dhash_bits(crop),
                "fg_dhash": _dhash_bits(fg),
                "edge_dhash": _dhash_bits(edges),
            }
        )

    findings = []
    for rule in logo_rules:
        templates = rule.get("deprecated_logo_hashes") or []
        if not templates:
            continue
        rule_id = rule["id"]
        rule_version = str(rule.get("version") or "1.0.0")
        rule_text = rule.get("rule_text") or rule.get("message") or ""
        quote, q_start, q_end = extract_verbatim_quote(rule_text, rule.get("rule_quote"))

        best_hit = None
        for tmpl in templates:
            if isinstance(tmpl, str):
                t_dhash = tmpl.strip().lower()
                t_dark = None
                t_edge = None
                t_raw = t_dhash
                t_sha = None
                t_label = "Deprecated logo"
            elif isinstance(tmpl, dict):
                t_dhash = (tmpl.get("dhash") or "").strip().lower()
                t_dark = (tmpl.get("dark_dhash") or "").strip().lower() or None
                t_edge = (tmpl.get("edge_dhash") or "").strip().lower() or None
                t_raw = (tmpl.get("raw_dhash") or "").strip().lower() or None
                t_sha = (tmpl.get("sha256") or "").strip().lower() or None
                t_label = tmpl.get("label") or "Deprecated logo"
            else:
                continue

            if t_sha and t_sha == asset_sha:
                best_hit = (0, "full", t_dhash or t_sha, t_label)
                break

            for rh in region_hashes:
                distances = []
                if t_dhash:
                    distances.append(_hamming_hex(rh["fg_dhash"], t_dhash))
                    distances.append(_hamming_hex(rh["raw_dhash"], t_dhash))
                if t_dark:
                    distances.append(_hamming_hex(rh["fg_dhash"], t_dark))
                    distances.append(_hamming_hex(rh["raw_dhash"], t_dark))
                if t_raw:
                    distances.append(_hamming_hex(rh["fg_dhash"], t_raw))
                    distances.append(_hamming_hex(rh["raw_dhash"], t_raw))
                edge_dist = _hamming_hex(rh["edge_dhash"], t_edge) if t_edge else None
                min_d = min(distances) if distances else 64
                hit_dist = None
                if min_d <= 7:
                    hit_dist = min_d
                elif edge_dist is not None and edge_dist <= 9:
                    hit_dist = edge_dist
                if hit_dist is not None:
                    if best_hit is None or hit_dist < best_hit[0]:
                        best_hit = (hit_dist, rh["region"], t_dhash or t_raw or "", t_label)

        if best_hit is not None:
            dist, region, matched_hash, label = best_hit
            sim_pct = round(((64 - dist) / 64.0) * 100.0, 1)
            findings.append(
                {
                    "finding_id": _stable_visual_finding_id(
                        rule_id, rule_version, asset_id, f"{region}:{matched_hash}"
                    ),
                    "rule_id": rule_id,
                    "rule_version": rule_version,
                    "rule_quote": quote,
                    "rule_quote_start": q_start,
                    "rule_quote_end": q_end,
                    "severity": rule.get("severity", "critical"),
                    "message": f"{rule.get('message', 'Deprecated logo detected')} ({label} in {region}, {sim_pct}% match on {asset_name})",
                    "evidence": f"{label} in {region} ({sim_pct}% match)",
                    "start_index": 0,
                    "end_index": 0,
                    "suggestion": rule.get("suggestion"),
                    "replacement": rule.get("replacement"),
                    "source_origin": "visual",
                    "channel": (channel or "all").lower(),
                    "visual_evidence": {
                        "check": "logo",
                        "asset_id": asset_id,
                        "asset_name": asset_name,
                        "region": region,
                        "label": label,
                        "hamming_distance": dist,
                        "similarity_pct": sim_pct,
                        "matched_hash": matched_hash,
                    },
                }
            )
    return findings


def run_ai_vision_inspection(
    raw: bytes,
    mime: str,
    asset_id: str,
    asset_name: str,
    active_rules: list[dict],
    channel: str = "all",
) -> list[dict]:
    """Optional constrained vision check when AI_PROVIDER/key is configured; always grounded server-side."""
    visual_rules = [
        r
        for r in active_rules
        if r.get("enabled", True) and r.get("rule_type") in {"visual_palette", "visual_logo"}
    ]
    if (
        not visual_rules
        or config.AI_PROVIDER not in {"openai", "openrouter", "gemini"}
        or not config.AI_API_KEY
    ):
        return []
    b64 = base64.b64encode(raw).decode("ascii")
    rules_payload = [
        {
            "rule_id": r["id"],
            "rule_version": r["version"],
            "rule_text": r["rule_text"],
        }
        for r in visual_rules
    ]
    is_gemini = (
        config.AI_PROVIDER == "gemini"
        or "generativelanguage.googleapis.com" in (config.AI_BASE_URL or "").lower()
    )
    is_openrouter_free = config.AI_PROVIDER == "openrouter" and (
        (config.AI_MODEL or "").strip().lower().endswith(":free")
        or (config.AI_MODEL or "").strip().lower() in {"openrouter/free", "openrouter/auto"}
    )
    base_url = (config.AI_BASE_URL or "").strip().rstrip("/")
    if base_url.endswith("/chat/completions"):
        endpoint_url = base_url
    elif (
        config.AI_PROVIDER == "gemini"
        and "generativelanguage.googleapis.com" in base_url.lower()
        and base_url.lower().endswith("/v1beta")
    ):
        endpoint_url = base_url + "/openai/chat/completions"
    else:
        endpoint_url = base_url + "/chat/completions"

    def _vision_payload(model_name: str) -> dict:
        body: dict = {
            "model": model_name,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "Inspect the supplied image strictly against the provided visual rules JSON. "
                        "Return JSON {\"findings\": [{\"rule_id\": ..., \"rule_version\": ..., "
                        "\"rule_quote\": <verbatim quote from rule_text>, \"region\": ..., \"message\": ...}]}. "
                        "Never invent rule IDs or paraphrase rule_quote."
                    ),
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": json.dumps({"rules": rules_payload})},
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:{mime};base64,{b64}"},
                        },
                    ],
                },
            ],
        }
        if is_gemini:
            body["max_tokens"] = 800
        else:
            body["store"] = False
            body["max_completion_tokens"] = 800
            if config.AI_PROVIDER == "openrouter":
                policy = getattr(config, "AI_DATA_COLLECTION", "")
                if policy == "deny" or (not policy and not is_openrouter_free):
                    body["provider"] = {"data_collection": "deny"}
        return body

    try:
        headers = {"Authorization": f"Bearer {config.AI_API_KEY}"}
        response = httpx.post(
            endpoint_url,
            headers=headers,
            json=_vision_payload(config.AI_MODEL),
            timeout=20,
        )
        if response.status_code == 404 and is_gemini:
            for candidate in (
                "gemini-3.5-flash-lite",
                "gemini-3.8-flash",
                "gemini-3.6-flash",
                "gemini-3.1-flash-lite",
                "gemini-2.5-flash-lite",
            ):
                if candidate == config.AI_MODEL:
                    continue
                response = httpx.post(
                    endpoint_url,
                    headers=headers,
                    json=_vision_payload(candidate),
                    timeout=20,
                )
                if response.status_code != 404:
                    break
        response.raise_for_status()
        raw_content = (response.json()["choices"][0]["message"]["content"] or "").strip()
        if raw_content.startswith("```"):
            raw_content = raw_content.strip("`")
            if raw_content.lower().startswith("json"):
                raw_content = raw_content[4:]
            raw_content = raw_content.strip()
        parsed = json.loads(raw_content)
        out = []
        for idx, item in enumerate(parsed.get("findings") or []):
            out.append(
                {
                    "finding_id": _stable_visual_finding_id(
                        str(item.get("rule_id", "")),
                        str(item.get("rule_version", "")),
                        asset_id,
                        f"ai-vis-{idx}",
                    ),
                    "rule_id": str(item.get("rule_id", "")),
                    "rule_version": str(item.get("rule_version", "")),
                    "rule_quote": str(item.get("rule_quote", "")),
                    "severity": "review",
                    "message": str(item.get("message", ""))[:500],
                    "evidence": str(item.get("region", "image")),
                    "start_index": 0,
                    "end_index": 0,
                    "source_origin": "visual",
                    "channel": (channel or "all").lower(),
                    "visual_evidence": {
                        "check": "ai_vision",
                        "asset_id": asset_id,
                        "asset_name": asset_name,
                        "region": str(item.get("region", "full")),
                    },
                }
            )
        return out
    except Exception:
        return []


def inspect_visual_asset(
    raw: bytes,
    mime: str,
    asset_id: str,
    asset_name: str,
    active_rules: list[dict],
    channel: str = "all",
) -> list[dict]:
    palette = inspect_palette_rules(raw, asset_id, asset_name, active_rules, channel=channel)
    logos = inspect_logo_rules(raw, asset_id, asset_name, active_rules, channel=channel)
    existing_rule_ids = {f["rule_id"] for f in palette + logos}
    ai_vis = [
        f
        for f in run_ai_vision_inspection(
            raw, mime, asset_id, asset_name, active_rules, channel=channel
        )
        if f.get("rule_id") not in existing_rule_ids
    ]
    return palette + logos + ai_vis
