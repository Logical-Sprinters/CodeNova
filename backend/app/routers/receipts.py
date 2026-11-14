
from fastapi import APIRouter, HTTPException

from app.receipts.store import get_receipt, load_receipts

router = APIRouter(
    prefix="/api/v1/receipts",
    tags=["Processing Receipts"],
)


@router.get("/")
async def list_receipts():
    receipts = load_receipts()

    return {
        "total": len(receipts),
        "receipts": receipts,
    }


@router.get("/{receipt_id}")
async def receipt_details(receipt_id: str):
    receipt = get_receipt(receipt_id)

    if not receipt:
        raise HTTPException(
            status_code=404,
            detail="Processing receipt not found.",
        )

    return receipt
