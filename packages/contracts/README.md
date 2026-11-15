# Shared Contracts

The JSON Schema files in this directory are design contracts for the broader BrandGuard product. Current FastAPI endpoints use handwritten Pydantic models in `backend/app/schemas/`; code generation and runtime validation against these JSON Schema files are not configured.

Files include rule, finding, approval, audit-entry, and processing-receipt schemas.

Contract changes should be reviewed with API/client behavior and tests. Schema shape validation does not enforce active-rule grounding, access control, or state transitions. Do not call these files the runtime single source of truth until generation/validation is implemented.
