
def run_ai_verification(content: str, brand_facts: list = None):
    """
    Grounded verification interface.
    Returns abstention when trusted brand facts are unavailable.
    """

    if not brand_facts:
        return {
            "status": "abstained",
            "message": "No verified brand facts available for comparison.",
            "findings": [],
        }

    # Actual LLM provider integration will use these
    # trusted facts as its only verification source.

    return {
        "status": "pending_provider",
        "message": "Trusted facts available; LLM provider integration required.",
        "findings": [],
    }
