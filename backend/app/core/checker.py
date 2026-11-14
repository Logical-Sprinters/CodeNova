"""The check engine: text + channel + live rules -> findings.

Deterministic on purpose.
  * It works with no network, no key and no rate limit.
  * Every finding is defensible in one sentence: this rule, this version, this span.
  * It cannot invent a rule. A model can, and one invented rule in a governance
    product is worse than no product at all.

Span offsets are Python code points. The copy this build handles is ASCII, where
that equals Dart's UTF-16 offsets; with emoji the two would drift, which is a
known, documented limit.
"""
import re
from dataclasses import dataclass, field

from . import statuses
from .rewrites import for_kind as rewrites_for

# A phrase detector: what to look for, which rule answers it, and how confidently.
# `rule_ids` is a preference list, not a guarantee: if none of them is live, the
# detector produces nothing rather than citing a rule that cannot be cited.
DETECTORS = [
    {
        "kind": "leadership",
        "label": "Market-leadership claim",
        "rule_ids": ["CLAI-001"],
        "status": statuses.NEEDS_REVIEWER,
        "pattern": re.compile(
            r"(#\s?1\b|number one|no\.\s?1\b|market leader|category leader|"
            r"best[- ]selling|world'?s (?:best|leading|number one))", re.I),
    },
    {
        "kind": "guarantee",
        "label": "Guaranteed outcome",
        "rule_ids": ["CLAI-002"],
        "status": statuses.NEEDS_REVIEWER,
        "pattern": re.compile(
            r"(guarantee[ds]?|100\s?%|risk[- ]free|never fails|always works|bulletproof)", re.I),
    },
    {
        "kind": "naming",
        "label": "Product name written as two words",
        "rule_ids": ["TERM-001"],
        "status": statuses.CONFIRMED,
        "pattern": re.compile(r"\bTask\s+Flow\b", re.I),
    },
    {
        "kind": "terminology",
        "label": "Project vs workspace",
        "rule_ids": ["TERM-002"],
        "status": statuses.INTERPRETATION,
        "pattern": re.compile(r"\bprojects?\b", re.I),
    },
    {
        "kind": "superlative",
        "label": "Superlative with nothing behind it",
        "rule_ids": [],
        "status": statuses.UNSUPPORTED,
        "pattern": re.compile(
            r"\b(the (?:fastest|easiest|simplest|most popular|most powerful)|"
            r"revolutionary|game[- ]changing|unrivalled|world[- ]class)\b", re.I),
    },
]


@dataclass
class Finding:
    """A finding before it is stored. `rule` is the exact live rule version cited."""
    kind: str
    status: str
    rule: dict
    span: tuple[int, int]
    message: str
    value: str = ""
    rewrites: list[dict] = field(default_factory=list)

    def __post_init__(self):
        if not self.rewrites:
            self.rewrites = rewrites_for(self.kind, self.value)


def _price_in(rule_text: str) -> str | None:
    match = re.search(r"\$(\d+(?:\.\d+)?)", rule_text)
    return match.group(1) if match else None


def _first_live(rules: list[dict], rule_ids: list[str]) -> dict | None:
    for rule_id in rule_ids:
        for rule in rules:
            if rule["rule_id"] == rule_id:
                return rule
    return None


def check(text: str, channel: str, live_rules: list[dict]) -> list[Finding]:
    """`live_rules` must come from live_rules_for_channel(); never filtered by hand."""
    findings: list[Finding] = []

    # 1. prices, one finding per mismatched figure per live price-sensitive rule
    for rule in live_rules:
        if not rule.get("price_sensitive"):
            continue
        canonical = _price_in(rule["rule_text"])
        if not canonical:
            continue
        for match in re.finditer(r"\$\s?(\d+(?:\.\d+)?)", text):
            if match.group(1) == canonical:
                continue
            findings.append(Finding(
                kind="price",
                status=statuses.CONFIRMED,
                rule=rule,
                span=(match.start(), match.end()),
                value=canonical,
                message=(f"Copy states ${match.group(1)}. {rule['rule_id']} v{rule['version']} "
                         f"is live and states ${canonical} per user per month."),
            ))

    # 2. phrases
    for detector in DETECTORS:
        rule = _first_live(live_rules, detector["rule_ids"]) if detector["rule_ids"] else None
        if detector["rule_ids"] and rule is None:
            continue  # its rule is not live for this channel today; say nothing
        for match in detector["pattern"].finditer(text):
            if any(f.span[0] <= match.start() < f.span[1] for f in findings):
                continue  # one finding per overlapping region
            if detector["status"] == statuses.UNSUPPORTED:
                message = (f"“{match.group(0)}” is a claim with no rule and no source behind it. "
                           f"Unsupported does not mean false — it means we cannot verify it here.")
            elif rule is None:
                message = f"“{match.group(0)}” needs a human decision."
            else:
                message = (f"“{match.group(0)}” — {detector['label'].lower()} "
                           f"({rule['rule_id']} v{rule['version']}).")
            findings.append(Finding(
                kind=detector["kind"],
                status=detector["status"],
                rule=rule,
                span=(match.start(), match.end()),
                message=message,
            ))

    # 3. a rule set that contradicts itself: this is the case where guessing would
    #    be worse than saying so, so it is escalated and never resolved here
    tone_rules = [r for r in live_rules if r["rule_id"] == "TONE-001"]
    opposing = [r for r in live_rules if r["rule_id"] == "TONE-002"]
    if tone_rules and opposing and channel == "social" and text.strip():
        a, b = tone_rules[0], opposing[0]
        findings.append(Finding(
            kind="conflict",
            status=statuses.CONFLICT,
            rule=b,
            span=(0, 0),
            message=(f"{a['rule_id']} v{a['version']} and {b['rule_id']} v{b['version']} are both "
                     f"live and give opposite instructions. We will not guess which one wins."),
        ))

    findings.sort(key=lambda f: f.span[0])
    return findings
