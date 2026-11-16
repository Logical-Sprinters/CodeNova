from fastapi import HTTPException

from app.config import DATA_DIR
from app import config
from app.storage import read_json

RULES_FILE = DATA_DIR / "brand_rules.json"


def load_rule_store():
    if config.STORAGE_BACKEND == "json" and not RULES_FILE.is_file():
        raise HTTPException(500, "Brand rules configuration is missing")
    result = read_json(RULES_FILE, {})
    if not isinstance(result.get("brands"), dict):
        raise HTTPException(500, "Invalid brand rules configuration")
    return result


def get_brand_rules(brand_name: str):
    brand = load_rule_store()["brands"].get(brand_name.strip().lower())
    if not brand:
        return None
    version = brand["current_version"]
    if version not in brand.get("versions", {}):
        raise HTTPException(500, "Current brand rules version is missing")
    return {"version": version, "rules": brand["versions"][version]["rules"]}


def get_brand_rule_versions(brand_name: str):
    brand = load_rule_store()["brands"].get(brand_name.strip().lower())
    if not brand:
        return None
    return {
        "brand_name": brand_name.strip(),
        "current_version": brand["current_version"],
        "available_versions": list(brand["versions"].keys()),
    }
