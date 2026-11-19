from pydantic import BaseModel, Field, field_validator
from typing import Literal


class TextContent(BaseModel):
    content: str = Field(min_length=1, max_length=200_000)

    @field_validator("content")
    @classmethod
    def nonblank_content(cls, value):
        if not value.strip():
            raise ValueError("Content must contain non-whitespace text.")
        return value  # Preserve exact submitted bytes for content hashes.


class BrandContent(TextContent):
    brand_name: str = Field(min_length=1, max_length=128)

    @field_validator("brand_name")
    @classmethod
    def nonblank_brand(cls, value):
        value = value.strip()
        if not value:
            raise ValueError("Brand name must not be blank.")
        return value


class BrandCheckRequest(BrandContent):
    content_type: Literal["text"] = "text"


class PreflightRequest(BaseModel):
    brand_name: str = Field(min_length=1, max_length=128)
    content: str = Field(default="", max_length=200_000)

    @field_validator("brand_name")
    @classmethod
    def nonblank_preflight_brand(cls, value):
        value = value.strip()
        if not value:
            raise ValueError("Brand name must not be blank.")
        return value


class ContentVersionRequest(TextContent):
    expected_version: int | None = Field(default=None, ge=1)


class Finding(BaseModel):
    rule_id: str
    severity: str
    message: str
    evidence: str
    start_index: int
    end_index: int
    suggestion: str | None = None
    replacement: str | None = None
    citations: list[dict] = Field(default_factory=list)


class BrandCheckResponse(BaseModel):
    check_id: str
    brand_name: str
    status: str
    findings: list[Finding]
    total_findings: int
    receipt_id: str
    content_version: int
    scan_status: str
    review_status: str
    rules_version: str | None = None
    ai_verification: dict | None = None
    visual_analysis: dict | None = None
    checked_content: str | None = None
    source_conflicts: list[dict] = Field(default_factory=list)


class ReviewDecisionRequest(BaseModel):
    decision: str
    note: str = Field(default="", max_length=4000)
    expected_version: int | None = Field(default=None, ge=1)


class ApprovalVerifyRequest(BrandContent):
    check_id: str = Field(min_length=1, max_length=128)

    @field_validator("check_id")
    @classmethod
    def nonblank_id(cls, value):
        value = value.strip()
        if not value:
            raise ValueError("Check ID must not be blank.")
        return value
