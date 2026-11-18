"""Conservative, explainable source-of-truth conflict detection.

Only enabled rules/guidelines and enabled, reviewer-verified facts participate.
A conflict is emitted only when two sources express the same normalized claim
with opposite explicit polarity (for example, "supports exports" vs
"does not support exports"). This intentionally favors precision over recall.
"""

import re

from app import config
from app.rules_store.store import load_rule_store
from app.storage import read_json

_NEGATIONS = {"not", "no", "never", "cannot", "can't", "doesn't", "isn't", "without"}
_STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "can", "for", "from",
    "in", "into", "is", "it", "of", "on", "or", "our", "the", "their",
    "this", "to", "with", "will", "your",
}
_WORDS = re.compile(r"[a-z0-9]+")
_SENTENCES = re.compile(r"[^.!?;\n]+[.!?;]?", re.MULTILINE)


def _polarity(sentence: str) -> bool:
    words = set(_WORDS.findall(sentence.lower()))
    return not bool(words & _NEGATIONS)


def _claim_key(sentence: str) -> frozenset[str]:
    words = set(_WORDS.findall(sentence.lower()))
    words -= _STOPWORDS
    words -= _NEGATIONS
    return frozenset(words)


def _source_sentences(source: dict):
    if source["type"] == "rule":
        text = " ".join(
            str(source.get(key) or "")
            for key in ("title", "description", "suggestion")
        )
    else:
        text = " ".join(
            str(source.get(key) or "")
            for key in ("title", "description", "content")
        )
    for sentence in _SENTENCES.findall(text):
        key = _claim_key(sentence)
        # Very short or generic claims are too ambiguous to compare safely.
        if len(key) >= 3:
            yield sentence.strip(), key, _polarity(sentence)


def _load_sources(brand_name: str) -> list[dict]:
    sources = []
    normalized_brand = brand_name.strip().casefold()

    rules_store = load_rule_store()
    brand = rules_store.get("brands", {}).get(normalized_brand)
    if brand:
        version = brand.get("current_version")
        for item in brand.get("versions", {}).get(version, {}).get("rules", []):
            if item.get("enabled", True):
                sources.append({
                    "id": item.get("id", "unknown"),
                    "type": "rule",
                    "title": item.get("name") or item.get("id", "Brand rule"),
                    "description": item.get("message", ""),
                    "suggestion": item.get("suggestion", ""),
                    "source_url": "",
                })

    for kind in ("guidelines", "facts"):
        path = config.DATA_DIR / f"library_{kind}.json"
        for item in read_json(path, []):
            if item.get("brand_name", "Acme").strip().casefold() != normalized_brand:
                continue
            if not item.get("enabled", True):
                continue
            if kind == "facts" and not item.get("verified", False):
                continue
            sources.append({
                "id": item.get("id", "unknown"),
                "type": "fact" if kind == "facts" else "guideline",
                "title": item.get("title", kind.title()),
                "description": item.get("description", ""),
                "content": item.get("content", ""),
                "source_url": item.get("source_url", ""),
            })
    return sources


def detect_source_conflicts(brand_name: str) -> list[dict]:
    """Return evidence-backed conflicts between distinct trusted sources."""
    claims = []
    for source in _load_sources(brand_name):
        for sentence, key, positive in _source_sentences(source):
            claims.append((source, sentence, key, positive))

    conflicts = []
    seen = set()
    for index, (left, left_text, left_key, left_positive) in enumerate(claims):
        for right, right_text, right_key, right_positive in claims[index + 1:]:
            if left["id"] == right["id"] or left_positive == right_positive:
                continue
            if left_key != right_key:
                continue
            pair = tuple(sorted((str(left["id"]), str(right["id"])))) + (
                " ".join(sorted(left_key)),
            )
            if pair in seen:
                continue
            seen.add(pair)
            conflicts.append({
                "conflict_id": f"source-conflict-{len(conflicts) + 1}",
                "status": "unresolved",
                "claim": " ".join(sorted(left_key)),
                "evidence": [
                    {
                        "source_id": left["id"],
                        "source_type": left["type"],
                        "source_title": left["title"],
                        "source_url": left.get("source_url", ""),
                        "statement": left_text,
                    },
                    {
                        "source_id": right["id"],
                        "source_type": right["type"],
                        "source_title": right["title"],
                        "source_url": right.get("source_url", ""),
                        "statement": right_text,
                    },
                ],
            })
    return conflicts
