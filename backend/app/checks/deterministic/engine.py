
import re

from app.schemas.brand import Finding
from app.rules_store.store import get_brand_rules


BASE_RULES = [
    {
        "id": "BG-001",
        "pattern": r"\blorem ipsum\b|\bTODO\b|\[insert[^\]]*\]",
        "severity": "warning",
        "message": "Unfinished placeholder detected.",
    },
    {
        "id": "BG-002",
        "pattern": r"\bguaranteed\b|\b100%\s*(?:safe|secure|effective)\b|\brisk[- ]free\b",
        "severity": "review",
        "message": "Potentially unsupported absolute claim. Verify before publication.",
    },
]


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
            findings.append(
                Finding(
                    rule_id=rule.get("id", rule.get("rule_id")),
                    severity=rule["severity"],
                    message=rule["message"],
                    evidence=match.group(),
                    start_index=match.start(),
                    end_index=match.end(),
                )
            )

    return findings
