"""Server-side finding grounding verification.

Every finding must cite an active rule ID + version, carry a verbatim substring
quote from that stored rule's text (or verified fact source), and reference a
valid content span. Ungrounded or stale findings are dropped, never softened.
"""

import copy


def _is_strict_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def extract_verbatim_quote(rule_text: str, preferred_quote: str | None = None) -> tuple[str, int, int]:
    text = rule_text or ""
    if preferred_quote and preferred_quote in text:
        idx = text.index(preferred_quote)
        return preferred_quote, idx, idx + len(preferred_quote)
    trimmed = text.strip()
    if not trimmed:
        return "", 0, 0
    snippet = trimmed[:220]
    idx = text.find(snippet)
    if idx < 0:
        idx = 0
        snippet = text[:220]
    return snippet, idx, idx + len(snippet)


def verify_finding_grounding(
    finding: dict,
    active_rules_by_id: dict[str, dict],
    content: str,
    active_facts_by_id: dict[str, dict] | None = None,
    ocr_text: str = "",
) -> tuple[bool, str | None]:
    if not isinstance(finding, dict):
        return False, "invalid_finding_shape"
    rule_id = finding.get("rule_id")
    rule_version = finding.get("rule_version")
    rule_quote = finding.get("rule_quote") or ""
    if not isinstance(rule_id, str) or not rule_id.strip():
        return False, "missing_rule_id"

    source_origin = finding.get("source_origin") or "caption"
    evidence = finding.get("evidence")
    start = finding.get("start_index")
    end = finding.get("end_index")

    # AI-FACT findings must ground against an active verified fact + verbatim fact quote + content span.
    if rule_id.startswith("AI-FACT-"):
        if source_origin not in {"caption", "image_ocr"}:
            return False, "invalid_source_origin"
        target = ocr_text if source_origin == "image_ocr" else content
        if (
            not isinstance(evidence, str)
            or not evidence
            or not _is_strict_int(start)
            or not _is_strict_int(end)
            or start < 0
            or end <= start
            or end > len(target)
            or target[start:end] != evidence
        ):
            return False, "stale_or_invalid_content_span"

        citations = finding.get("citations") or []
        if not citations or not active_facts_by_id:
            return False, "missing_fact_citations"
        for c in citations:
            fact = active_facts_by_id.get(c.get("fact_id"))
            quote = c.get("quote") or ""
            if not fact or len(quote.strip()) < 6 or quote not in fact.get("content", ""):
                return False, "invented_or_inactive_fact_citation"
        primary_fact = active_facts_by_id.get(citations[0].get("fact_id"))
        if not primary_fact:
            return False, "missing_primary_fact"
        expected_version = str(primary_fact.get("version") or "1.0.0")
        if str(rule_version) != expected_version:
            return False, "stale_fact_version"
        if len(rule_quote.strip()) < 6 or rule_quote not in primary_fact.get("content", ""):
            return False, "paraphrased_or_missing_rule_quote"
        qs = finding.get("rule_quote_start")
        qe = finding.get("rule_quote_end")
        if qs is not None and qe is not None:
            if (
                not _is_strict_int(qs)
                or not _is_strict_int(qe)
                or qs < 0
                or qe <= qs
                or qe > len(primary_fact["content"])
                or primary_fact["content"][qs:qe] != rule_quote
            ):
                return False, "stale_rule_quote_span"
        return True, None

    rule = active_rules_by_id.get(rule_id)
    if rule is None:
        return False, "invented_or_inactive_rule_id"
    if str(rule_version) != str(rule.get("version", "1.0.0")):
        return False, "stale_or_mismatched_rule_version"

    rule_type = rule.get("rule_type", "regex")
    if rule_type in {"visual_palette", "visual_logo"}:
        if source_origin != "visual" or not isinstance(finding.get("visual_evidence"), dict) or not finding["visual_evidence"]:
            return False, "missing_visual_evidence"
    else:
        if source_origin not in {"caption", "image_ocr"}:
            return False, "invalid_source_origin"
        target = ocr_text if source_origin == "image_ocr" else content
        if (
            not isinstance(evidence, str)
            or not evidence
            or not _is_strict_int(start)
            or not _is_strict_int(end)
            or start < 0
            or end <= start
            or end > len(target)
            or target[start:end] != evidence
        ):
            return False, "stale_or_invalid_content_span"

    rule_text = rule.get("rule_text") or ""
    min_quote_len = min(4, len(rule_text.strip()))
    if min_quote_len == 0 or len(rule_quote.strip()) < min_quote_len or rule_quote not in rule_text:
        return False, "paraphrased_or_missing_rule_quote"

    qs = finding.get("rule_quote_start")
    qe = finding.get("rule_quote_end")
    if qs is not None and qe is not None:
        if (
            not _is_strict_int(qs)
            or not _is_strict_int(qe)
            or qs < 0
            or qe <= qs
            or qe > len(rule_text)
            or rule_text[qs:qe] != rule_quote
        ):
            return False, "stale_rule_quote_span"

    return True, None


def filter_grounded_findings(
    findings: list[dict],
    active_rules: list[dict],
    content: str,
    active_facts: list[dict] | None = None,
    ocr_text: str = "",
) -> tuple[list[dict], list[dict]]:
    rules_by_id = {r["id"]: r for r in active_rules if r.get("id")}
    facts_by_id = {f["id"]: f for f in (active_facts or []) if f.get("id")}
    grounded = []
    dropped = []
    for item in findings or []:
        ok, reason = verify_finding_grounding(
            item,
            rules_by_id,
            content,
            active_facts_by_id=facts_by_id,
            ocr_text=ocr_text,
        )
        if ok:
            grounded.append(copy.deepcopy(item))
        else:
            dropped.append({"finding": copy.deepcopy(item), "drop_reason": reason})
    return grounded, dropped
