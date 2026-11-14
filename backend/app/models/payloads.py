"""Request bodies. Validation that can be done here is done here; validation that
must be impossible to bypass lives in the schema."""
from pydantic import BaseModel, Field

MAX_TEXT = 20_000


class NewContent(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_TEXT)
    channel: str = Field(default="social", min_length=1, max_length=40)
    title: str | None = Field(default=None, max_length=200)
    publish_date: str | None = None


class NewVersion(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_TEXT)


class OverrideRequest(BaseModel):
    reason_text: str = Field(min_length=3, max_length=500)
    reason_code: str = Field(
        default="rule_unclear",
        pattern="^(rule_unclear|not_applicable|approved_exception|source_outdated)$",
    )
