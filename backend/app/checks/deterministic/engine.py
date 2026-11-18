import hashlib
import regex as re
from fastapi import HTTPException

from app.checks.grounding import extract_verbatim_quote
from app.rules_store.store import DEFAULT_BASE_RULES, resolve_active_rules
from app.schemas.brand import Finding

BASE_RULES = DEFAULT_BASE_RULES


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


def _stable_finding_id(rule_id: str, rule_version: str, start: int, end: int, origin: str) -> str:
    raw = f"{rule_id}:{rule_version}:{origin}:{start}:{end}".encode("utf-8")
    return "fnd-" + hashlib.sha256(raw).hexdigest()[:16]


def run_deterministic_checks(
    content: str,
    brand_name: str,
    check_at=None,
    channel: str = "all",
    source_origin: str = "caption",
    active_rules: list[dict] | None = None,
):
    findings = []
    if active_rules is None:
        active_rules, _ = resolve_active_rules(
            brand_name, check_at=check_at, channel=channel
        )
    try:
        for rule in active_rules:
            if not rule.get("enabled", True):
                continue
            if rule.get("rule_type", "regex") != "regex" or not rule.get("pattern"):
                continue
            rule_id = rule.get("id", rule.get("rule_id"))
            rule_version = str(rule.get("version") or "1.0.0")
            rule_text = rule.get("rule_text") or rule.get("message") or ""
            quote, q_start, q_end = extract_verbatim_quote(
                rule_text, rule.get("rule_quote")
            )
            for match in re.finditer(
                rule["pattern"], content, flags=re.IGNORECASE, timeout=0.2
            ):
                suggestion, replacement = get_suggestion(rule, match.group())
                findings.append(
                    Finding(
                        finding_id=_stable_finding_id(
                            rule_id, rule_version, match.start(), match.end(), source_origin
                        ),
                        rule_id=rule_id,
                        rule_version=rule_version,
                        rule_quote=quote,
                        rule_quote_start=q_start,
                        rule_quote_end=q_end,
                        severity=rule["severity"],
                        message=rule["message"],
                        evidence=match.group(),
                        start_index=match.start(),
                        end_index=match.end(),
                        suggestion=suggestion,
                        replacement=replacement,
                        source_origin=source_origin,
                        channel=(channel or "all").lower(),
                    )
                )
    except (TimeoutError, re.error) as error:
        raise HTTPException(
            422,
            "A configured rule exceeded its execution budget or is invalid. A reviewer must fix that rule.",
        ) from error
    return findings
