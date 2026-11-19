from datetime import datetime, timezone
from enum import Enum
from typing import Literal
from uuid import uuid4

from pydantic import BaseModel, Field, field_validator


def parse_optional_timestamp(value: str | None) -> str | None:
    if value is None:
        return None
    raw = value.strip()
    if not raw:
        return None
    normalized = raw[:-1] + "+00:00" if raw.endswith(("Z", "z")) else raw
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise ValueError("Timestamp must be a valid ISO-8601 date/time.") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat()


class OverrideReason(str, Enum):
    FALSE_POSITIVE = "FALSE_POSITIVE"
    APPROVED_EXCEPTION = "APPROVED_EXCEPTION"
    AMBIGUOUS_RULE_TEXT = "AMBIGUOUS_RULE_TEXT"
    OUTDATED_RULE_OR_FACT = "OUTDATED_RULE_OR_FACT"
    CONTEXTUAL_QUALIFIER = "CONTEXTUAL_QUALIFIER"
    CHANNEL_EXEMPTION = "CHANNEL_EXEMPTION"


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
    content_type: Literal["text", "multimodal"] = "text"
    check_at: str | None = Field(default=None, max_length=64)
    channel: str = Field(default="all", min_length=1, max_length=64)
    asset_ids: list[str] = Field(default_factory=list, max_length=10)
    submit_for_review: bool = True
    parent_check_id: str | None = Field(default=None, max_length=128)

    @field_validator("check_at")
    @classmethod
    def valid_check_at(cls, value):
        return parse_optional_timestamp(value)

    @field_validator("channel")
    @classmethod
    def clean_channel(cls, value):
        cleaned = value.strip().lower()
        if not cleaned:
            raise ValueError("Channel must not be blank.")
        return cleaned

    @field_validator("parent_check_id")
    @classmethod
    def clean_parent_check_id(cls, value):
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class PreflightRequest(BrandContent):
    check_at: str | None = Field(default=None, max_length=64)
    channel: str = Field(default="all", min_length=1, max_length=64)
    asset_ids: list[str] = Field(default_factory=list, max_length=10)

    @field_validator("check_at")
    @classmethod
    def valid_check_at(cls, value):
        return parse_optional_timestamp(value)

    @field_validator("channel")
    @classmethod
    def clean_channel(cls, value):
        cleaned = value.strip().lower()
        if not cleaned:
            raise ValueError("Channel must not be blank.")
        return cleaned


class ContentVersionRequest(TextContent):
    expected_version: int | None = Field(default=None, ge=1)
    check_at: str | None = Field(default=None, max_length=64)
    channel: str | None = Field(default=None, min_length=1, max_length=64)
    asset_ids: list[str] | None = Field(default=None, max_length=10)
    submit_for_review: bool = True

    @field_validator("check_at")
    @classmethod
    def valid_check_at(cls, value):
        return parse_optional_timestamp(value)

    @field_validator("channel")
    @classmethod
    def clean_channel(cls, value):
        if value is None:
            return None
        cleaned = value.strip().lower()
        if not cleaned:
            raise ValueError("Channel must not be blank.")
        return cleaned


class Finding(BaseModel):
    finding_id: str = Field(default_factory=lambda: str(uuid4()))
    rule_id: str
    rule_version: str = "1.0.0"
    rule_quote: str = ""
    rule_quote_start: int | None = None
    rule_quote_end: int | None = None
    severity: str
    message: str
    evidence: str
    start_index: int
    end_index: int
    suggestion: str | None = None
    replacement: str | None = None
    source_origin: str = "caption"
    channel: str = "all"
    overridden: bool = False
    override: dict | None = None
    visual_evidence: dict | None = None
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
    parent_check_id: str | None = None
    rules_version: str | None = None
    check_at: str | None = None
    channel: str = "all"
    active_rule_versions: dict[str, str] = Field(default_factory=dict)
    dropped_ungrounded_count: int = 0
    conflicts: list[dict] = Field(default_factory=list)
    conflict_id: str | None = None
    asset_ids: list[str] = Field(default_factory=list)
    ocr_text: str = ""
    visual_summary: list[dict] = Field(default_factory=list)
    ai_verification: dict | None = None


class PreflightResponse(BaseModel):
    status: Literal["clean", "warnings_detected", "conflict_detected"]
    brand_name: str
    channel: str
    check_at: str
    findings: list[Finding]
    total_findings: int
    conflicts: list[dict] = Field(default_factory=list)
    asset_ids: list[str] = Field(default_factory=list)
    ocr_text: str = ""
    visual_summary: list[dict] = Field(default_factory=list)
    elapsed_ms: float


class ReviewDecisionRequest(BaseModel):
    decision: str
    note: str = Field(default="", max_length=4000)
    expected_version: int | None = Field(default=None, ge=1)


class ReviewAmendRequest(BaseModel):
    decision: Literal["approved", "rejected", "changes_requested"]
    reason: str = Field(min_length=3, max_length=2000)
    expected_version: int | None = Field(default=None, ge=1)

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, value):
        cleaned = value.strip()
        if len(cleaned) < 3:
            raise ValueError("Provide a reason of at least 3 characters.")
        return cleaned


class ApprovalVerifyRequest(BrandContent):
    check_id: str = Field(min_length=1, max_length=128)
    verify_at: str | None = Field(default=None, max_length=64)
    asset_ids: list[str] = Field(default_factory=list, max_length=10)

    @field_validator("check_id")
    @classmethod
    def nonblank_id(cls, value):
        value = value.strip()
        if not value:
            raise ValueError("Check ID must not be blank.")
        return value

    @field_validator("verify_at")
    @classmethod
    def valid_verify_at(cls, value):
        return parse_optional_timestamp(value)


class FindingOverrideRequest(BaseModel):
    reason_code: OverrideReason
    note: str = Field(default="", max_length=2000)


class ClarityTicketUpdateRequest(BaseModel):
    status: Literal["open", "acknowledged", "resolved"]
    resolution_note: str = Field(default="", max_length=2000)


class ConflictResolveRequest(BaseModel):
    winning_source_type: Literal["rule", "fact"]
    winning_source_id: str = Field(min_length=1, max_length=128)
    resolution_note: str = Field(default="", max_length=2000)
    auto_recheck: bool = True

    @field_validator("winning_source_id")
    @classmethod
    def nonblank_source_id(cls, value):
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("winning_source_id must not be blank.")
        return cleaned
