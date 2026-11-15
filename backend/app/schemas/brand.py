from pydantic import BaseModel, Field
from typing import List, Optional


class BrandCheckRequest(BaseModel):
    brand_name: str = Field(..., min_length=1)
    content: str = Field(..., min_length=1)
    content_type: str = "text"


class Finding(BaseModel):
    rule_id: str
    severity: str
    message: str
    evidence: str
    start_index: int
    end_index: int
    suggestion: Optional[str] = None
    replacement: Optional[str] = None


class BrandCheckResponse(BaseModel):
    check_id: str
    brand_name: str
    status: str
    findings: List[Finding]
    total_findings: int
    receipt_id: str | None = None


class ReviewDecisionRequest(BaseModel):
    decision: str
    reviewer: str = "Admin"
    note: str = ""


class ApprovalVerifyRequest(BaseModel):
    check_id: str
    brand_name: str
    content: str
