import regex as re
from fastapi import HTTPException

from app.schemas.brand import Finding
from app.rules_store.store import get_brand_rules

BASE_RULES = [
    {
        "id": "BG-001",
        "pattern": r"\blorem ipsum\b|\bTODO\b|\[insert[^\]]*\]",
        "severity": "warning",
        "message": "Unfinished placeholder detected.",
        "suggestion": "Replace this placeholder with complete, relevant content.",
        "replacement": "Please insert verified and relevant content here.",
    },
    {
        "id": "BG-002",
        "pattern": r"\bguarantee(?:s|d)?(?:\s+\w+){0,3}|\b100%\s*(?:safe|secure|effective)\b|\brisk[- ]free\b",
        "severity": "review",
        "message": "Potentially unsupported absolute claim. Verify before publication.",
        "suggestion": "Avoid absolute guarantees unless supported by verifiable evidence.",
    },
]


def get_suggestion(rule, evidence):
    if rule.get("id") != "BG-002":
        return rule.get("suggestion"), rule.get("replacement")

    text = evidence.lower()

    if "safe" in text:
        return rule["suggestion"], "designed with security controls"

    if "secure" in text:
        return rule["suggestion"], "designed with security measures"

    if "effective" in text:
        return rule["suggestion"], "designed to help improve results"

    if "guarantee" in text:
        return rule["suggestion"], "designed for high availability"

    if "risk-free" in text or "risk free" in text:
        return rule["suggestion"], "designed with appropriate safeguards"

    return rule.get("suggestion"), None


def run_deterministic_checks(content: str, brand_name: str):
    findings = []
    brand_data = get_brand_rules(brand_name)
    all_rules = BASE_RULES + (brand_data["rules"] if brand_data else [])
    try:
        for rule in all_rules:
            if not rule.get("enabled", True):
                continue
            required_phrase = str(rule.get("required_phrase") or "").strip()
            if required_phrase and required_phrase.casefold() not in content.casefold():
                findings.append(
                    Finding(
                        rule_id=rule.get("id", rule.get("rule_id")),
                        severity=rule["severity"],
                        message=rule["message"],
                        evidence="",
                        start_index=len(content),
                        end_index=len(content),
                        suggestion=rule.get("suggestion")
                        or f"Add the required wording: {required_phrase}",
                    )
                )
            pattern = str(rule.get("pattern") or "").strip()
            if not pattern:
                continue
            for match in re.finditer(pattern, content, flags=re.IGNORECASE, timeout=0.2):
                suggestion, replacement = get_suggestion(rule, match.group())
                findings.append(
                    Finding(
                        rule_id=rule.get("id", rule.get("rule_id")),
                        severity=rule["severity"],
                        message=rule["message"],
                        evidence=match.group(),
                        start_index=match.start(),
                        end_index=match.end(),
                        suggestion=suggestion,
                        replacement=replacement,
                    )
                )
    except (TimeoutError, re.error) as error:
        raise HTTPException(
            422,
            "A configured rule exceeded its execution budget or is invalid. A reviewer must fix that rule.",
        ) from error
    return findings
