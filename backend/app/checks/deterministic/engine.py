import re

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
    brand_rules = brand_data["rules"] if brand_data else []

    all_rules = BASE_RULES + brand_rules

    for rule in all_rules:
        for match in re.finditer(
            rule["pattern"],
            content,
            flags=re.IGNORECASE,
        ):
            suggestion, replacement = get_suggestion(
                rule,
                match.group(),
            )

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

    return findings