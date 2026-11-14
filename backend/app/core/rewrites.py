"""Three repairs for every finding, one per strategy.

Templates, not a model. That is the honest description of what this is, and it
has the property that matters at 2am: it cannot fail and cannot invent a rule.

  A surgical       - the smallest edit that satisfies the rule
  B brand_balanced - keeps the voice of the brand guidelines
  C channel_native - written the way the channel is actually written
"""
STRATEGIES = (("A", "surgical"), ("B", "brand_balanced"), ("C", "channel_native"))

_TEMPLATES: dict[str, dict[str, str]] = {
    "price": {
        # A replaces the figure in place; B and C replace the whole sentence, because
        # "just $34 per user per month per user" is not a repair, it is a new typo.
        "surgical": "${value}",
        "brand_balanced": "TaskFlow Pro is ${value} per user per month.",
        "channel_native": "TaskFlow Pro. ${value} per user, per month.",
    },
    "leadership": {
        "surgical": "",
        "brand_balanced": "a task app teams actually rely on",
        "channel_native": "the task app that sticks",
    },
    "guarantee": {
        "surgical": "",
        "brand_balanced": "built to keep your team on track",
        "channel_native": "your team, on track",
    },
    "naming": {
        "surgical": "TaskFlow",
        "brand_balanced": "TaskFlow",
        "channel_native": "TaskFlow",
    },
    "terminology": {
        "surgical": "workspace",
        "brand_balanced": "workspace",
        "channel_native": "workspace",
    },
    "superlative": {
        "surgical": "",
        "brand_balanced": "fast to set up and easy to keep tidy",
        "channel_native": "quick to start, tidy to keep",
    },
    "conflict": {
        "surgical": "TaskFlow Pro is $34 per user per month. Teams set it up in an afternoon.",
        "brand_balanced": "TaskFlow Pro is $34 per user per month. Your team picks it up fast and keeps it tidy.",
        "channel_native": "TaskFlow Pro. $34 per user. Set up before lunch.",
    },
}


# Which options rewrite a whole sentence rather than the matched phrase.
SENTENCE_SCOPE = {"price": {"B", "C"}}


def for_kind(kind: str, value: str = "") -> list[dict]:
    """Three options for one finding. `value` is the rule's own figure, if it has one."""
    templates = _TEMPLATES.get(kind, _TEMPLATES["conflict"])
    wide = SENTENCE_SCOPE.get(kind, set())
    return [
        {
            "option_label": label,
            "strategy": strategy,
            "rewrite_text": templates[strategy].replace("{value}", value).strip(),
            "scope": "sentence" if label in wide else "span",
        }
        for label, strategy in STRATEGIES
    ]
