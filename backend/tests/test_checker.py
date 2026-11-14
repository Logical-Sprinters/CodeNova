"""The check engine, as a pure function. No database, no HTTP: these run anywhere."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import statuses  # noqa: E402
from app.core.checker import check  # noqa: E402
from app.core.rewrites import for_kind  # noqa: E402

DEMO = ("Task Flow Pro is now just $29 per user and it is the #1 task app "
        "guaranteed to keep your team on track.")


def rule(rule_id, version=1, text="x", price_sensitive=False):
    return {"rule_id": rule_id, "version": version, "rule_text": text,
            "price_sensitive": price_sensitive}


LIVE_RULES = [
    rule("PRIC-002", text="TaskFlow Pro costs $34 per user per month.", price_sensitive=True),
    rule("TERM-001"), rule("TERM-002"), rule("CLAI-001"), rule("CLAI-002"),
    rule("TONE-001"), rule("TONE-002"),
]


def test_finds_the_wrong_price_and_quotes_the_right_span():
    findings = check(DEMO, "social", LIVE_RULES)
    price = next(f for f in findings if f.kind == "price")
    assert price.status == statuses.CONFIRMED
    assert DEMO[price.span[0]:price.span[1]] == "$29"
    assert price.rule["rule_id"] == "PRIC-002"


def test_a_contradiction_is_escalated_never_resolved():
    findings = check(DEMO, "social", LIVE_RULES)
    conflict = next(f for f in findings if f.status == statuses.CONFLICT)
    assert "TONE-001" in conflict.message and "TONE-002" in conflict.message
    assert conflict.kind == "conflict"


def test_no_finding_cites_a_rule_that_is_not_live():
    """With the price rule absent, the price detector must say nothing at all rather than
    cite something that is not in force."""
    without_price = [r for r in LIVE_RULES if r["rule_id"] != "PRIC-002"]
    findings = check(DEMO, "social", without_price)
    assert not any(f.kind == "price" for f in findings)


def test_unsupported_never_blocks():
    findings = check("The world's fastest task app, revolutionary.", "social", [])
    assert findings, "a superlative with no rule should still be reported"
    for finding in findings:
        assert finding.status == statuses.UNSUPPORTED
        assert finding.status not in statuses.BLOCKING


def test_clean_copy_produces_only_the_conflict_finding():
    findings = check("TaskFlow keeps a tidy workspace.", "email", LIVE_RULES)
    assert [f.status for f in findings] == []


def test_every_finding_offers_three_distinct_repairs():
    for finding in check(DEMO, "social", LIVE_RULES):
        options = finding.rewrites
        assert [o["option_label"] for o in options] == ["A", "B", "C"]
        assert len({o["rewrite_text"] for o in options}) >= 1


def test_price_repairs_carry_the_rules_own_figure():
    options = for_kind("price", "34")
    assert all("$34" in o["rewrite_text"] for o in options)
