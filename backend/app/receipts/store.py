
import json
from pathlib import Path
from uuid import uuid4
from datetime import datetime, timezone

RECEIPTS_FILE = Path(__file__).with_name("receipts.json")


def load_receipts():
    if not RECEIPTS_FILE.exists():
        return []

    with open(RECEIPTS_FILE, "r", encoding="utf-8") as file:
        return json.load(file)


def save_receipts(receipts):
    temp_file = RECEIPTS_FILE.with_suffix(".tmp")

    with open(temp_file, "w", encoding="utf-8") as file:
        json.dump(receipts, file, indent=4)

    temp_file.replace(RECEIPTS_FILE)


def create_receipt(data: dict):
    receipts = load_receipts()

    receipt = {
        "receipt_id": str(uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        **data,
    }

    receipts.append(receipt)
    save_receipts(receipts)

    return receipt


def get_receipt(receipt_id: str):
    return next(
        (r for r in load_receipts() if r["receipt_id"] == receipt_id),
        None,
    )
