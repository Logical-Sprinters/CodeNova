
import json
from pathlib import Path

RULES_FILE = Path(__file__).with_name("brand_rules.json")


def load_rule_store():
    with open(RULES_FILE, "r", encoding="utf-8") as file:
        return json.load(file)


def get_brand_rules(brand_name: str):
    store = load_rule_store()

    brand = store["brands"].get(brand_name.strip().lower())

    if not brand:
        return None

    version = brand["current_version"]

    return {
        "version": version,
        "rules": brand["versions"][version]["rules"],
    }


def get_brand_rule_versions(brand_name: str):
    store = load_rule_store()

    brand = store["brands"].get(brand_name.strip().lower())

    if not brand:
        return None

    return {
        "brand_name": brand_name,
        "current_version": brand["current_version"],
        "available_versions": list(brand["versions"].keys()),
    }
