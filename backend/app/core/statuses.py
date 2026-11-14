"""The five finding statuses, and what each one is allowed to do.

This module is the single place where "does this block approval?" is answered.
The frontend mirrors these names in its own model; it never decides them.
"""

CONFIRMED = "CONFIRMED_RULE_MATCH"
INTERPRETATION = "AI_INTERPRETATION"
UNSUPPORTED = "UNSUPPORTED"
CONFLICT = "SOURCE_CONFLICT_OR_EXPIRED"
NEEDS_REVIEWER = "NEEDS_AUTHORISED_REVIEWER"

# Only these two stop an approval. UNSUPPORTED deliberately does not: it records a
# gap in our evidence, and treating a gap as proof of wrongdoing is exactly the
# behaviour this product exists to replace.
BLOCKING = (CONFIRMED, CONFLICT)

LABELS = {
    CONFIRMED: "Confirmed rule match",
    INTERPRETATION: "Interpretation",
    UNSUPPORTED: "Unsupported",
    CONFLICT: "Source conflict",
    NEEDS_REVIEWER: "Needs a reviewer",
}

ACTIONS = {
    CONFIRMED: "BLOCK_EXPORT",
    CONFLICT: "FLAG_REVIEW",
    NEEDS_REVIEWER: "FLAG_REVIEW",
    INTERPRETATION: "ADVISORY",
    UNSUPPORTED: "ADVISORY",
}
