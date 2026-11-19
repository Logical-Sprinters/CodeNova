> **Status (Implemented):** Phases 1–4 plus the `Profile → My profile` personal identity sheet (with internal `CONNECTED BACKEND` / DB stack rows omitted from the UI) & in-app `Password & sessions` change-password flow, AI compatibility + `ENABLE_AI.bat` / `manage.py configure-ai` & `test-ai` / `POST /api/v1/system/ai-test` live verification probe, **60-minute time-boxed decision reversal (`POST /api/v1/reviews/{id}/amend`) & `REVOKED` cryptographic seals**, Approval Ledger inspection + amendment dialogs, duplicate-version/notification fixes, real-time shell/tab synchronization, clean submission labeling, `Request changes` + Creator Edit & Resubmit flow, 2-step Audit Inspection → Submit for authorised review, newest-first sorting, Light-mode default, Unseen/Seen notification sections, Remember me session persistence, post-submit redirect to Reviews, non-destructive `Edit as new check` for Approved checks, and author/local-time metadata are implemented across `backend/` and `mobile/` (`153` backend pytest cases — `151 passed, 2 skipped` without local Tesseract; `10` Flutter test files with `85+` tests; see `README.md` and `START_HERE.md` for local SQLite default setup and `docs/AI_SETUP.md` for AI verification). Sections below preserve the original Round 3 engineering design.

# BrandGuard Round 3 — Complete End-to-End Engineering Blueprint

**Repo:** `Logical-Sprinters/CodeNova` (branch `smeet_final`, commit `f6c0e22`)  
**Goal:** Ship all **3 Round-3 Core Governance Improvements** + **4 High-Contrast Product Differentiators** cleanly end-to-end across backend, database, AI/multimodal pipeline, frontend UI, and automated tests in **one day**.

---

## 0. Current Codebase Baseline & Existing Bugs Found

### What Exists Today
- **Backend (`backend/`)**: FastAPI (`app/main.py`, `app/web.py`) with a single-transaction SQLAlchemy repository (`app/database.py` using `bg_entities` and `bg_documents` on SQLite by default or PostgreSQL/Supabase) and a JSON test adapter (`app/storage.py`).
- **Auth (`app/auth_service.py`, `app/routers/authentication.py`)**: Local PBKDF2-SHA256 + JWT (`creator@brandguard.demo` / `u1`, `reviewer@brandguard.demo` / `u2`, password `Demo@12345`) or Supabase Auth + signed email hook.
- **Checks (`app/checks/deterministic/engine.py`, `app/checks/llm/verifier.py`)**: Regex engine + optional OpenAI/OpenRouter retrieval over verified facts (`AI_PROVIDER=disabled` by default).
- **Frontend (`mobile/` + `browser_preview/`)**: Flutter mobile-first app (`mobile/lib/`) with a precompiled CanvasKit web bundle (`browser_preview/`) served same-origin by `app/web.py` / `serve.py`.
- **Current Tests**: `backend/.venv/bin/pytest -q` passes **113 tests** (`tests/` + `tests_secure/`).

### Pre-Existing Mismatches & Gaps to Fix First
1. **Missing Profile & Preferences Backend Routes (Broken in `f6c0e22`)**:
   - `mobile/lib/core/network/brandguard_api_service.dart` already calls `PATCH /api/v1/auth/profile` and `GET`/`PUT /api/v1/auth/preferences` (and `mobile/test/profile_settings_test.dart` tests them against mocks), **but those endpoints do not exist in `backend/app/routers/authentication.py`**. They currently 404/405 against the real backend.
2. **Hardcoded Base Rules in Python**:
   - `BASE_RULES` (`BG-001`, `BG-002`) in `backend/app/checks/deterministic/engine.py` are hardcoded dicts rather than versioned stored rules with `rule_text`, `effective_from`, and `version`.
3. **Restrictive Content/File Input Guards**:
   - `BrandCheckRequest.content_type` in `backend/app/schemas/brand.py` is locked to `Literal["text"] = "text"`.
   - `backend/app/routers/files.py` explicitly rejects images (`415`) and does not include `Pillow` / `pytesseract` / `tesseract-ocr`.
4. **Unused Legacy Demo Files**:
   - `mobile/lib/features/demo/demo_governance_screens.dart`, `demo_analytics_screen.dart`, and `mobile/lib/core/demo/demo_review_store.dart` are leftover unreferenced mock screens (live routes use `ServerRecordsScreen` and `AnalyticsScreen`).

---

## 1. Architecture of the 7 Required Additions

### Improvement 1 — No Finding Without Evidence (Grounding Enforced in Code)
**Problem today:** `engine.py` returns `{rule_id, severity, message, evidence, start_index, end_index}` with no rule version and no verbatim quote from stored rule text. Findings are never re-verified server-side before reviewers read them.

**Implementation:**
1. **Rich Stored Rule Schema (`rules_store/store.py`, `data/brand_rules.json`, `routers/library.py`)**:
   - Migrate `BG-001`, `BG-002`, and brand rules into stored versioned rule records with:
     - `id` (e.g., `BG-001`, `ACME-001`, `COMP-14`, `VIS-02`, `VIS-05`)
     - `version` (per-rule semantic/integer version, e.g. `"1.0.0"`, `"2.0.0"`)
     - `name`, `rule_type` (`"regex"` | `"visual_palette"` | `"visual_logo"` | `"fact_claim"`)
     - `rule_text` (canonical stored policy clause — **required non-empty prose**)
     - `pattern` (for regex rules), `allowed_hex_colors` / `banned_hex_colors` / `deprecated_logo_hashes` (for visual rules)
     - `severity` (`"warning"` | `"review"` | `"critical"`)
     - `message`, `suggestion`, `replacement`
     - `effective_from`, `expires_at`, `supersedes`
     - `topic_key`, `canonical_value`
     - `channels` (e.g. `["all"]` or `["instagram", "web", "email"]`)
     - `owner_id` (defaults to `"u2"` / creator reviewer)
     - `enabled`
2. **Mandatory Finding Grounding Fields (`app/schemas/brand.py`)**:
   Every `Finding` (deterministic, visual, or AI) MUST carry:
   - `finding_id`: deterministic/UUID identifier (so findings can be individually overridden)
   - `rule_id`: active rule ID at check time
   - `rule_version`: exact rule version active at check time
   - `rule_quote`: **exact verbatim substring** present inside that stored rule version's `rule_text`
   - `rule_quote_start`, `rule_quote_end`: character offsets inside `rule_text`
   - `evidence`, `start_index`, `end_index`: exact substring/span in submitted text (or OCR text / visual metadata for images)
   - `source_origin`: `"caption"` | `"image_ocr"` | `"image_visual"`
3. **Server-Side Grounding Verification Gate (`app/checks/grounding.py`)**:
   - Implement `verify_finding_grounding(finding, rule_lookup, content, check_at) -> bool`:
     1. Rule ID exists in the active rule set resolved at `check_at` (or verified fact citation maps to an active verified fact at `check_at`).
     2. `finding.rule_version == active_rule.version`.
     3. `finding.rule_quote` is non-empty (min length >= 6) and exists **verbatim** inside `active_rule.rule_text` (`finding.rule_quote in active_rule.rule_text`).
     4. For text/OCR findings: `target_text[start_index:end_index] == evidence` (exact span check).
     5. For visual findings: `visual_evidence` includes verified color hex/coverage or perceptual logo hash match.
   - Run `filter_grounded_findings(...)`:
     - **On check creation / version resubmit** (`routers/brand.py`)
     - **On every read before a reviewer or creator sees findings** (`GET /api/v1/reviews`, `GET /api/v1/receipts/{id}`, `GET /api/v1/history`) — re-verified server-side against the immutable rule snapshot / store!
   - **Strict Drop Policy**: Ungrounded findings (invented rule IDs, paraphrased quotes, stale/expired versions, mismatched spans) are **dropped completely** (never softened into warnings) and recorded in `dropped_ungrounded_count` + `audit_log` (`action="ungrounded_finding_dropped"`).
4. **Conflict Abstention**:
   - Whenever 2+ active rules/facts contradict on a `topic_key`, abstain instead of picking a winner (see Differentiator 2).

**Pass Bar Verification:**
- Unit + API tests injecting invented `rule_id`, paraphrased `rule_quote`, stale `rule_version`, and mismatched text span → **100% dropped** on both check creation and reviewer read gate.
- **10/10** seeded conflict scenarios return `abstained_conflict` without emitting a guessed finding.

---

### Improvement 2 — Correct Over Time (Point-in-Time Rules & Facts)
**Problem today:** Rules have only a brand-level `current_version` string and no `effective_from`, `expires_at`, or `supersedes`. Fact retrieval ignores dates. `verify_approval` only says `"Brand rules have changed since approval."` without naming which rule changed.

**Implementation:**
1. **Temporal Metadata on Rules & Facts**:
   - Add to both rules (`brand_rules`) and fact sources (`library_facts`):
     - `effective_from`: ISO-8601 UTC timestamp (required; defaults to rule/fact creation time if omitted on legacy items)
     - `expires_at`: ISO-8601 UTC timestamp or `null` (exclusive upper bound: active when `effective_from <= check_at < expires_at`)
     - `supersedes`: ID or `"<rule_id>@<version>"` of the rule/fact it replaces
     - `version`: explicit version string per rule and per fact (e.g. `"1.0.0"`, `"2.0.0"`)
2. **Point-in-Time Resolver (`rules_store/store.py` + `checks/llm/verifier.py`)**:
   - `resolve_active_rules(brand_name: str, check_at: datetime, channel: str = "all") -> tuple[list[dict], dict]`:
     - Scans all stored rule revisions for the brand (plus base rules).
     - Keeps rules where `enabled == True`, `effective_from <= check_at`, and (`expires_at is None or check_at < expires_at`).
     - Filters out any rule superseded by another rule that is **also active at `check_at`** (`supersedes` link resolution).
     - Filters by `channel` (`"all"` in `rule.channels` or `channel in rule.channels`).
     - Returns both the active rules list and a deterministic `rules_snapshot_digest` + `{rule_id: version}` map.
   - `retrieve_facts(content, brand_name, facts=None, check_at=None)`:
     - Applies the same `effective_from <= check_at < expires_at` and `supersedes` exclusion on verified facts.
3. **Temporal Check Parameter**:
   - `BrandCheckRequest`, `ContentVersionRequest`, and `PreflightRequest` accept optional `check_at: datetime | None = None` (defaults to `datetime.now(timezone.utc)`), plus `channel: str = "all"`.
   - Stored on `review_records` and `receipts` (`check_at`, `channel`, `active_rule_versions: {rule_id: version}`).
4. **Named Rule Diff in Approval Verification (`approval/store.py` & `routers/reviews.py`)**:
   - In `verify_approval(...)`: compare the `active_rule_versions` captured at check/approval time against the currently active rules at `verify_at` (defaults to `now()`).
   - Identify **exact rule changes**:
     - `added`: rules now active that were not active at approval time
     - `modified`: same `rule_id`, different `version`
     - `expired`: rules active at approval time whose `expires_at <= verify_at`
     - `superseded`: rules replaced by a newer `supersedes` rule
   - Return `rule_changes: [...]` and name the exact changed rule(s) in `reason` (e.g., `"Approval invalidated because rule ACME-PRICE-01 changed (v1.0.0 -> v2.0.0); rule BG-PROMO-OLD expired."`).

**Pass Bar Verification:**
- Test case: identical copy `"Transfer fee is ₹0"` checked at `T1` (before rule), `T2` (while old ₹0 rule active / passed), and `T3` (after ₹25 rule supersedes ₹0 rule / flagged) yields **3 distinct, exact verdicts**, and verifying `T2` approval at `T3` explicitly names the superseding rule ID.

---

### Improvement 3 — No Override Without Learning (Override Telemetry)
**Problem today:** Reviewers can only approve or reject an entire submission. Individual findings cannot be overridden, no coded reasons exist, and no friction telemetry or clarity tickets exist.

**Implementation:**
1. **Coded Override Reasons (`app/overrides/store.py`)**:
   - Strict enum `OverrideReason`:
     - `FALSE_POSITIVE` — "Rule matched harmless or unrelated phrasing"
     - `APPROVED_EXCEPTION` — "Executive/legal pre-approved exception applies"
     - `AMBIGUOUS_RULE_TEXT` — "Rule wording is unclear for this edge case"
     - `OUTDATED_RULE_OR_FACT` — "Rule or fact appears stale vs current policy"
     - `CONTEXTUAL_QUALIFIER` — "Required disclaimer/qualifier is present nearby"
     - `CHANNEL_EXEMPTION` — "Rule does not apply cleanly to this channel"
2. **Override Endpoints (`app/routers/overrides.py`)**:
   - `POST /api/v1/reviews/{check_id}/findings/{finding_id}/override`
     - **Guards**: Authenticated `reviewer` or `admin` ONLY (`403` for creator role); cannot override on own submission (`409`); finding must exist in the current version's grounded findings (`404`).
     - **Validation**: `reason_code` must be one of `OverrideReason` (`422` if missing or free-text only); `note` (`min_length=3`, optional or short explanation).
     - **Persistence**: Saves override record in `finding_overrides` (`bg_entities` collection) with `{override_id, check_id, content_version, finding_id, brand_name, channel, rule_id, rule_version, reason_code, note, reviewer_id, created_at}` and marks that finding as `overridden: true` with its override metadata in the review record.
     - **Audit & Notification**: Writes `override_finding` event to `audit_log`.
   - `GET /api/v1/overrides`: Filterable by `rule_id`, `brand_name`, `channel`, `reason_code`.
   - `GET /api/v1/clarity-tickets`: Lists aggregated friction tickets (reviewer/admin/owner visibility).
   - `PATCH /api/v1/clarity-tickets/{ticket_id}`: Allows reviewer/admin/guideline owner to transition ticket `status` (`open` → `acknowledged` → `resolved`) with resolution notes.
3. **Friction Aggregation → Clarity Tickets (Zero Rule Mutation)**:
   - On every new override, count overrides grouped by `(brand_name, rule_id, rule_version, channel)` (or overall `(brand_name, rule_id, rule_version)` across channels).
   - When count >= `OVERRIDE_FRICTION_THRESHOLD` (default `3`, configurable via `config.OVERRIDE_FRICTION_THRESHOLD` for testing), automatically create (or update if an `open` ticket already exists for that rule+version+channel) a **Clarity Ticket**:
     - `ticket_id`, `brand_name`, `rule_id`, `rule_version`, `channel`, `owner_id` (from rule's `owner_id`), `override_count`, `reason_breakdown` (`{reason_code: count}`), `sample_overrides`, `status: "open"`, `created_at`, `updated_at`.
     - Sends in-app notification to `owner_id` (`notifications.py`).
   - **Hard Safety Invariant**: Override aggregation **NEVER** writes to `brand_rules` (`rules_store`). Rules remain 100% immutable unless explicitly edited via `PUT /api/v1/library/rules/{id}` by a reviewer.

**Pass Bar Verification:**
- Seeded overrides without a valid coded `reason_code` fail (`422`).
- Seeded friction patterns (`>= 3` overrides on `ACME-001` / `channel="instagram"` or `BG-002`) generate exact `clarity_tickets` assigned to the guideline owner, with a cryptographic check verifying `brand_rules` hash/content is **100% unchanged**.

---

### Differentiator 1 — Multimodal Enforcement (Text + Visuals in One Pass)
**Problem today:** `files.py` only parses `.txt`, `.md`, `.pdf`. Images fail with `415`, and `brand/check` only checks plain text.

**Implementation:**
1. **Dependencies (`backend/requirements.txt` & `Dockerfile`)**:
   - Add `pillow`, `pytesseract`, `numpy` to `backend/requirements.txt`.
   - Install `tesseract-ocr` in sandbox and add `RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr` to `Dockerfile` so Antideploy builds cleanly.
2. **Expand File Upload & Metadata (`backend/app/routers/files.py`)**:
   - Support `.png`, `.jpg`, `.jpeg`, `.webp` alongside `.txt`, `.md`, `.pdf` (max 5 MB).
   - For image uploads:
     - Compute `file_sha256` (`hashlib.sha256(raw).hexdigest()`), read dimensions `(width, height)`, format, extract OCR text + word bounding boxes (`pytesseract.image_to_data`), and extract dominant hex colors (`Pillow` quantization).
     - Return `{id, name, content_type, bytes, file_sha256, width, height, extracted_text, dominant_colors, is_image: true}` (and support `GET /api/v1/files/{id}/raw` or `/download` for UI image preview!).
3. **Visual Brand Inspector (`backend/app/checks/visual/inspector.py`)**:
   Run **two parallel passes** (`ThreadPoolExecutor` / `asyncio.gather`) when `asset_ids` include images:
   - **Pass 1 — OCR + Copy Fusion**:
     - Combine submitted caption text (`source_origin="caption"`) and extracted OCR text (`source_origin="image_ocr"`) while tracking their separate offsets.
     - Run `run_deterministic_checks(...)` + temporal fact verification on **both** caption and OCR text so text hidden inside banners cannot bypass rules.
   - **Pass 2 — Visual Brand Check**:
     - **Dominant Palette Check (`VIS-02`)**: Extract top dominant colors (ignoring near-white/transparent background noise if configured, or including full-bleed background hex) and measure RGB distance (Delta) against active `visual_palette` rules (`allowed_hex_colors` / `banned_hex_colors`). If an unapproved dominant color like `#1E40AF` exceeds the coverage threshold (e.g., `>= 15%`) and does not match the allowed palette (`#0F172A`, `#22A895`, `#FFFFFF`), emit a grounded finding citing `VIS-02` + verbatim `rule_quote` + `visual_evidence: {detected_hex, coverage_pct, allowed_hex}`.
     - **Deprecated Logo Check (`VIS-05`)**:
       - Store deprecated logo perceptual hash(es) / reference crop signatures on `VIS-05` rule (and allow uploading/registering deprecated logo templates in library!).
       - Scan banner regions (top-left, top-right, full corners, sliding window crops) using Pillow dHash/aHash Hamming distance + normalized cross-correlation (`numpy`). When a match hits below threshold, emit a grounded finding citing `VIS-05` + region box (`top-left`) + similarity score + verbatim `rule_quote`.
       - **Optional AI Vision Augmentation**: When `AI_PROVIDER` (`openai`/`openrouter`) and `AI_API_KEY` are configured, optionally run a strict-schema vision call constrained to return ONLY active `VIS-*` `rule_id`s + verbatim `rule_quote`s, still filtered by the server-side grounding gate!
4. **Unified Check Request (`POST /api/v1/brand/check`)**:
   - Update `BrandCheckRequest`:
     - `content_type: Literal["text", "multimodal", "image"] = "text"` (update old test in `test_regressions.py` that asserted `"image"` returns 422, or support `"multimodal"` while keeping an invalid type test like `"video"` returning 422 so regression intent stays intact!).
     - `asset_ids: list[str] = []` (validates user ownership of uploaded assets).
     - Runs text + OCR + visual checks in one pass, builds composite SHA-256 over `content` + sorted `asset_sha256`s, and returns unified grounded findings.

---

### Differentiator 2 — Source-of-Truth Conflict Escalation (Refusing to Hallucinate)
**Problem today:** When two internal rules or fact sheets disagree (e.g., Marketing Playbook `"Zero-Fee Transfers"` vs Legal Fact Sheet `"₹25 fee applies from Nov 2026"`), nothing detects the contradiction.

**Implementation:**
1. **Topic Key & Canonical Value**:
   - Rules and Fact Sources both support `topic_key` (e.g., `"transfer_fee"`, `"yield_rate"`, `"sla_uptime"`) and `canonical_value` (e.g., `"0"`, `"25_inr"`, `"99.9%"`) plus optional `topic_keywords` (e.g., `["transfer", "fee", "zero-fee"]`).
2. **Pre-Check Conflict Gate (`backend/app/checks/conflicts.py`)**:
   - Before checking a draft at `check_at`:
     - Collect all active rules and all active verified facts at `check_at` for `brand_name` (within `channel`).
     - Group by `topic_key` (ignoring empty `topic_key`).
     - A conflict exists on `topic_key` if **2 or more active sources** (rule-vs-rule, fact-vs-fact, or rule-vs-fact) share that `topic_key` with **different normalized `canonical_value`s** (and neither explicitly `supersedes` the other while both remain active at `check_at`).
     - Check whether the draft content (or OCR text) references that `topic_key` (via keywords/value tokens) OR if `strict_brand_conflicts=True` (default `True` whenever active conflicting clauses touch the draft's topics/keywords).
   - **When Conflict Triggers**:
     - Persist a `conflict_record` (`bg_entities` collection `conflicts`) with `conflict_id`, `brand_name`, `topic_key`, `check_id`, `check_at`, `status: "open"`, and `clauses: [...]` (both sides side-by-side: `source_type`, `source_id`, `title`, `version`, `effective_from`, `canonical_value`, `excerpt`, `owner_id`).
     - Check returns immediately with:
       - `status: "review_paused_conflict"`
       - `scan_status: "abstained_conflict"`
       - `review_status: "paused_conflict"`
       - `findings: []` (abstained — **zero guessed findings!**)
       - `conflicts: [...]`
     - Reviewer decision endpoint (`PATCH /api/v1/reviews/{check_id}/decision`) refuses approval (`409 Conflict`) while `status == "paused_conflict"`.
3. **Admin / Reviewer Conflict Resolution (`POST /api/v1/conflicts/{conflict_id}/resolve`)**:
   - Requires `reviewer` or `admin` role.
   - Body: `{winning_source_type, winning_source_id, resolution_note}`.
   - Marks losing rule(s)/fact(s) as `superseded` / sets `expires_at = now()` (with `supersedes` link updated on winner if applicable), marks `conflict_record` `resolved`, logs `resolve_conflict` in `audit_log`, and optionally auto-re-evaluates or unlocks the paused check so the creator/reviewer can re-run cleanly.

---

### Differentiator 3 — The "Single-Comma Tamper" Live Demo (SHA-256 Cryptographic Lock)
**Problem today:** `verify_approval` returns only `{valid: bool, reason: str}`. Changing 1 character gives no diff, no explicit `VOIDED` status badge, and no image-byte sealing.

**Implementation:**
1. **Immutable Approval Seal (`approval_seals` collection in `app/approval/store.py`)**:
   - When a reviewer approves (`PATCH /api/v1/reviews/{check_id}/decision` with `decision="approved"`):
     - Compute `composite_hash = sha256(canonical_json({"brand_name": ..., "content": exact_content, "asset_hashes": sorted_asset_hashes}))` alongside `content_hash = sha256(exact_content)`.
     - Append an immutable seal record:
       `{seal_id, check_id, content_version, brand_name, snapshot_text, snapshot_asset_hashes, content_hash, composite_hash, rules_version, active_rule_versions, reviewer_id, sealed_at}`.
2. **Enhanced Verification Endpoint (`POST /api/v1/approvals/verify` & `POST /api/v1/approvals/verify-upload`)**:
   - Accept `{check_id, brand_name, content, asset_ids?, verify_at?}` (and optional multipart endpoint accepting re-uploaded text/image file bytes).
   - Compute live `submitted_hash` and `submitted_composite_hash` and compare against the seal:
     - **Match + Rules Current**:
       - `valid: true`, `seal_status: "SEALED"`, `sealed_hash`, `submitted_hash`, `sealed_at`, `reviewer_id`, `reason: "SEALED — Exact content, assets, and active rules match the approved cryptographic hash."`
     - **Content/Asset Hash Mismatch (Even 1 comma/space/pixel)**:
       - `valid: false`, `seal_status: "VOIDED_TAMPERED"`
       - `reason: "APPROVAL VOIDED — Post-Sign-Off Tampering Detected."`
       - `approved_hash`, `submitted_hash`
       - **Word-by-Word + Inline Token Diff (`difflib.SequenceMatcher`)**:
         - `diff_segments`: list of `{op: "equal" | "replace" | "delete" | "insert", approved_text, current_text}`
         - `tampered_tokens`: concise summary of exact changed words/punctuation (e.g. `["up to 8% -> guaranteed 8%"]` or `[", -> <removed>"]`)
         - `unified_diff`: standard diff string
       - Logs `tamper_detected` event in `audit_log` (preserving original immutable seal!).
     - **Rules Changed / Expired / Superseded**:
       - `valid: false`, `seal_status: "INVALIDATED_RULE_CHANGE"`
       - `rule_changes`: exact changed rules from Improvement 2.
     - **Not Approved / Pending / Rejected / Paused Conflict**:
       - `valid: false`, `seal_status: "NOT_APPROVED"`.

---

### Differentiator 4 — Shift-Left Pre-Flight Check (From Gatekeeper to Co-Pilot)
**Problem today:** Creators must click "Run Brand Check", which writes permanent DB checks, receipts, and reviewer notifications on every draft tweak.

**Implementation:**
1. **Stateless Pre-Flight Endpoint (`POST /api/v1/brand/preflight`)**:
   - Authenticated endpoint accepting `{brand_name, content, channel="all", check_at=None, asset_ids=[]}`.
   - Runs **in-memory only** (zero writes to `review_records`, `receipts`, `notifications`, or `audit_log`):
     - Conflict Gate check (returns `conflicts` if any active sources clash)
     - Deterministic grounded checks (`engine.py` + `grounding.py`)
     - Fast local verified-fact numeric/claim lookup (`verifier.py` lexical/claim match — e.g. catching `"12% returns"` or `"₹0 fee"` against verified active fact sheets without waiting for an external LLM call!)
     - Visual check if `asset_ids` provided
   - Returns:
     - `status`: `"clean"` | `"warnings_detected"` | `"conflict_detected"`
     - `findings`: list of grounded findings with `start_index`, `end_index`, `evidence`, `severity`, `rule_id`, `rule_version`, `rule_quote`, `suggestion`, `replacement`
     - `conflicts`: active conflict objects
     - `elapsed_ms`: execution latency

---

## 2. Complete Backend File & Endpoint Map

### New / Updated Backend Files
| File | Responsibility |
|---|---|
| `backend/requirements.txt` & `Dockerfile` | Add `pillow`, `pytesseract`, `numpy`, and `tesseract-ocr` apt package |
| `backend/app/config.py` | Add `OVERRIDE_FRICTION_THRESHOLD` (default `3`), seed demo rules/facts/logos |
| `backend/app/database.py` | Register `KEYS` for new collections: `finding_overrides`, `clarity_tickets`, `conflicts`, `approval_seals`, `user_preferences` |
| `backend/app/routers/authentication.py` | **Fix existing bug**: add `PATCH /api/v1/auth/profile` & `GET/PUT /api/v1/auth/preferences` |
| `backend/app/rules_store/store.py` | Rule-level versions, `effective_from`/`expires_at`/`supersedes`, `resolve_active_rules()`, `diff_rules_snapshot()`, `BASE_RULES` stored properly |
| `backend/app/checks/grounding.py` | **New**: verbatim `rule_quote` validation + server-side `filter_grounded_findings()` drop gate |
| `backend/app/checks/conflicts.py` | **New**: `topic_key` conflict detector & abstention gate + resolution helper |
| `backend/app/checks/visual/inspector.py` | **New**: OCR (`pytesseract`), Pillow dominant hex palette check (`VIS-02`), perceptual-hash deprecated logo detection (`VIS-05`), optional grounded AI vision |
| `backend/app/checks/deterministic/engine.py` | Emit grounded findings with `finding_id`, `rule_version`, verbatim `rule_quote` + offsets, replacement suggestions |
| `backend/app/checks/llm/verifier.py` | Point-in-time fact filtering (`check_at`), rule-grounded citations, optional fast local fact-claim preflight check |
| `backend/app/overrides/store.py` | **New**: Coded-reason overrides, friction aggregation, Clarity Ticket creation (zero rule mutation) |
| `backend/app/approval/store.py` | Immutable `approval_seals`, composite text+asset SHA-256, `difflib` tamper diff, named rule-change diff |
| `backend/app/routers/brand.py` | Upgrade `/check` & `/{id}/versions` (multimodal, `check_at`, conflict gate, grounding gate), add `POST /api/v1/brand/preflight` |
| `backend/app/routers/files.py` | Support image uploads (`.png`, `.jpg`, `.jpeg`, `.webp`), OCR + color extraction, asset preview bytes endpoint |
| `backend/app/routers/reviews.py` | Re-verify finding grounding on read, block paused-conflict approval, create immutable seal on approve, upgrade `/approvals/verify` + add `/approvals/verify-upload` |
| `backend/app/routers/overrides.py` | **New**: `POST /api/v1/reviews/{check_id}/findings/{finding_id}/override`, `GET /api/v1/overrides`, `GET/PATCH /api/v1/clarity-tickets` |
| `backend/app/routers/conflicts.py` | **New**: `GET /api/v1/conflicts`, `POST /api/v1/conflicts/{conflict_id}/resolve` |
| `backend/app/routers/library.py` | Support temporal fields (`effective_from`, `expires_at`, `supersedes`), `rule_text`, `topic_key`, `canonical_value`, `channels`, visual palette/logo fields, logo image upload |
| `backend/data/brand_rules.json` & seed data | Starter rules (`BG-001`, `BG-002`, `COMP-14`, `VIS-02`, `VIS-05`, point-in-time pricing rule) + sample deprecated logo & fintech demo seed endpoint/script |

### New / Updated API Endpoints Summary
- `PATCH /api/v1/auth/profile` & `GET/PUT /api/v1/auth/preferences` (fixes existing Flutter client mismatch)
- `POST /api/v1/brand/preflight` (Shift-Left real-time Co-Pilot)
- `POST /api/v1/brand/check` (now supports `check_at`, `channel`, `asset_ids`, `content_type: text|multimodal`, conflict pause, grounding gate)
- `POST /api/v1/files` (now supports `.png`, `.jpg`, `.jpeg`, `.webp` with OCR + hex colors + perceptual hashes)
- `GET /api/v1/files/{asset_id}/download` (serves image bytes cleanly for preview)
- `POST /api/v1/reviews/{check_id}/findings/{finding_id}/override` (coded reason required)
- `GET /api/v1/overrides`
- `GET /api/v1/clarity-tickets` & `PATCH /api/v1/clarity-tickets/{ticket_id}`
- `GET /api/v1/conflicts` & `POST /api/v1/conflicts/{conflict_id}/resolve`
- `POST /api/v1/approvals/verify` & `POST /api/v1/approvals/verify-upload` (returns `SEALED` / `VOIDED_TAMPERED` / `INVALIDATED_RULE_CHANGE`, word-level diff, named rule changes)
- `POST /api/v1/demo/seed-round3` (optional reviewer/admin-guarded helper or startup seed so all 7 demo flows can be tested immediately without manual DB setup)

---

## 3. Frontend UI Plan (`mobile/` + `browser_preview/`)

> **Important Note for Teammate:** Install Flutter SDK (`flutter` / `dart`) locally (or in the build container) before editing/building `mobile/`, because after updating Dart screens we must run `flutter analyze`, `flutter test`, and `flutter build web --no-web-resources-cdn` and copy/sync to `browser_preview/` so `serve.py` serves the updated web bundle!

### Screen-by-Screen UI Changes
1. **New Brand Check (`mobile/lib/features/checks/new_brand_check_screen.dart`) — Differentiators 1, 2, 4 & Improvement 2**:
   - **Shift-Left Split-Screen / Live Co-Pilot**:
     - Add a `500ms` debounce listener on the draft editor calling `POST /api/v1/brand/preflight`.
     - On wide/web screens (`width >= 820px`): split screen — Editor on left, live **Rule Radar** panel on right. On narrow mobile screens: inline underlined/highlighted risky phrases + collapsible live **Rule Radar** card below the editor.
     - Each live radar card shows `rule_id` (`COMP-14`), `rule_version`, verbatim `rule_quote`, and a **1-click "Apply Fix"** button.
   - **Point-in-Time Date & Channel Picker**:
     - Add optional `Check Date (check_at)` date/time selector (`Now` vs historical/future date for the time-travel demo) and `Channel` selector (`All`, `Instagram`, `LinkedIn`, `Email`, `Web`).
   - **Multimodal Banner Upload**:
     - Update `document_picker.dart` to accept `['txt', 'md', 'pdf', 'png', 'jpg', 'jpeg', 'webp']`.
     - Show image thumbnail preview + extracted OCR text preview + detected dominant hex color swatches right in the attachment card, and pass `asset_ids` + `content_type: 'multimodal'` to `/api/v1/brand/check`.
2. **Findings & Conflict Screen (`mobile/lib/features/checks/findings_evidence_screen.dart`) — Improvements 1, 3 & Differentiators 1, 2**:
   - **Conflict Escalation Banner**: When `status == "review_paused_conflict"`, render an amber **"REVIEW PAUSED — INTERNAL RULE CONFLICT"** card showing both conflicting clauses side-by-side (`effective_from`, `version`, `canonical_value`, `quote`), plus **"Resolve & Pin Active Rule"** action for Reviewers/Admins.
   - **Grounded Evidence Block on Every Finding**: Show `rule_id · v{rule_version}`, verbatim `RULE CLAUSE QUOTE` box, `source_origin` pill (`CAPTION` / `IMAGE OCR` / `VISUAL PALETTE` / `VISUAL LOGO`), and for visual findings show color swatch comparison (`#1E40AF` vs allowed `#0F172A`) or flagged region (`top-left`).
   - **Coded-Reason Override Modal (for Reviewers)**: Add **"Override Finding"** button on each finding opening a dialog with mandatory coded reason dropdown (`OverrideReason` enum) + note input.
3. **Approval Verification (`mobile/lib/features/approvals/approval_verification_screen.dart`) — Improvement 2 & Differentiator 3**:
   - **Cryptographic Seal Badge**:
     - Green: `SEALED — SHA-256: 9f86d081...`
     - Bright Red: `APPROVAL VOIDED — Post-Sign-Off Tampering Detected`
     - Amber: `INVALIDATED — Rule Change Detected` (lists exact `rule_changes`: e.g. `ACME-PRICE-01 v1.0 -> v2.0`)
   - **Side-by-Side / Inline Diff Renderer**: Renders `diff_segments` highlighting deleted/tampered tokens in red and original approved tokens in green (even for a single changed comma!).
   - Also allow verifying an image re-upload alongside text.
4. **Review Queue & Clarity Tickets (`mobile/lib/features/reviews/review_queue_screen.dart` + new `ClarityTicketsScreen`)**:
   - Show conflict status badges and ungrounded-drop telemetry count in review cards.
   - Add **Clarity Tickets** module (accessible from Workspace Hub & Guidelines Hub) listing open friction tickets per `(rule_id, rule_version, channel)` with reason-code breakdown bar and **Acknowledge / Resolve** actions (clearly noting zero automatic rule changes occur).
5. **Library Screen (`mobile/lib/features/guidelines/library_screen.dart`)**:
   - Add inputs for `rule_text`, `effective_from`, `expires_at`, `supersedes`, `topic_key`, `canonical_value`, `channels`, and visual rule config (`VIS-02` palette hexes / `VIS-05` deprecated logo image upload).

---

## 4. One-Day Execution Plan & Task Split

### Phase 1 (Hours 0–2): Core Models, Bug Fixes & Temporal Grounding
- **Backend**:
  - Fix `/api/v1/auth/profile` & `/api/v1/auth/preferences`.
  - Add new entity collections in `database.py`.
  - Refactor `rules_store/store.py` + `brand_rules.json` + `library.py` to support `rule_text`, per-rule `version`, `effective_from`, `expires_at`, `supersedes`, `topic_key`, `canonical_value`, `channels`, `owner_id`.
  - Implement `checks/grounding.py` (drop gate on write & read) and update `engine.py` + `verifier.py` for verbatim rule quotes and point-in-time `check_at` filtering.

### Phase 2 (Hours 2–4): Conflict Gate, Overrides + Clarity Tickets, Tamper Lock & Pre-Flight
- **Backend**:
  - Implement `checks/conflicts.py` + `routers/conflicts.py` (conflict pause + side-by-side clauses + pin-winner resolution).
  - Implement `overrides/store.py` + `routers/overrides.py` (coded-reason validation + friction threshold → `clarity_tickets`, zero rule mutation).
  - Upgrade `approval/store.py` + `routers/reviews.py` (immutable `approval_seals`, composite SHA-256, `difflib` token diff, named rule-change diff).
  - Add `POST /api/v1/brand/preflight` in `routers/brand.py`.

### Phase 3 (Hours 4–6): Multimodal Banner Pipeline
- **Backend**:
  - Install `tesseract-ocr`, `pillow`, `pytesseract`, `numpy`; update `requirements.txt` & `Dockerfile`.
  - Expand `routers/files.py` to ingest images (`png/jpg/webp`), compute SHA-256, OCR text, and color metadata.
  - Implement `checks/visual/inspector.py`: OCR+caption merge, dominant hex check (`VIS-02`), perceptual-hash deprecated logo check (`VIS-05`), plus optional grounded vision prompt.
  - Wire `asset_ids` into `/brand/check`, `/brand/preflight`, and composite approval seals.

### Phase 4 (Hours 6–8): Flutter UI & Web Bundle Rebuild
- **Frontend (`mobile/`)**:
  - Update `BrandGuardApiService` & `document_picker.dart`.
  - Build Shift-Left split-screen Co-Pilot + date/channel picker + image upload in `NewBrandCheckScreen`.
  - Build Conflict Pause card + Override Coded-Reason modal + grounded rule quotes in `FindingsEvidenceScreen` & `ReviewQueueScreen`.
  - Build `SEALED` / `VOIDED` badge + word-level diff viewer in `ApprovalVerificationScreen`.
  - Build `ClarityTicketsScreen` and temporal/topic fields in `LibraryScreen`.
  - Run `flutter analyze`, `flutter test`, and `flutter build web --no-web-resources-cdn` → sync into `browser_preview/`.

### Phase 5 (Hours 8–10): Exhaustive Tests & End-to-End Demo Verification
- Run all **113 existing tests** (ensuring zero regressions) + new Round-3 test suite covering every pass bar:
  1. Grounding gate rejects 100% of invented rule IDs, paraphrased quotes, and stale spans (both on check creation and reviewer read).
  2. 10/10 conflicting rule/fact pairs abstain cleanly (`review_paused_conflict`) and resolve via admin pin.
  3. Point-in-time check of identical text before, during, and after rule change yields 3 distinct, exact verdicts; approval verify names changed rules.
  4. Coded overrides reject missing/invalid reasons (`422`); seeded friction opens exact `clarity_tickets` with 0 rule mutations.
  5. Multimodal banner PNG with clean caption flags `VIS-02` unapproved hex + `VIS-05` deprecated logo + OCR-hidden text violation.
  6. Single-comma edit after approval flips `SEALED` → `VOIDED_TAMPERED` with exact word diff.
  7. Pre-flight endpoint returns inline highlights & suggestions without creating DB records/notifications.
  8. Full smoke run (`start_backend.py --web` + Playwright/HTTP smoke test against live server).

---

## 5. Judge Demo Script (End-to-End Walkthrough)

1. **Shift-Left Co-Pilot**: Type `"Enjoy guaranteed 12% returns on your balance"` in the Draft Editor → within 500ms, `"guaranteed"` highlights inline and Rule Radar cites `COMP-14` with 1-click replacement `"projected up to"`.
2. **Source-of-Truth Conflict Escalation**: Upload/enable conflicting Marketing (`"Zero-Fee Transfers"`) vs. Legal (`"₹25 fee applies from Nov 2026"`) on `topic_key="transfer_fee"`. Submit draft mentioning transfer fees → Amber **REVIEW PAUSED — INTERNAL RULE CONFLICT** card shows both clauses side-by-side → Reviewer clicks **Resolve & Pin Active Rule**.
3. **Time-Travel Rule Check**: Re-run identical transfer-fee copy dated `Oct 2026` vs `Nov 2026` vs post-expiry → 3 exact, different verdicts.
4. **Multimodal Banner Check**: Upload a fintech promo PNG banner whose caption passes, but background uses `#1E40AF` and top-left has the 2024 logo + OCR text `"100% risk-free"` → flags `VIS-02`, `VIS-05`, and `BG-002` with exact grounded rule quotes.
5. **Override Telemetry → Clarity Ticket**: Reviewer overrides a finding 3 times across submissions using coded reason `AMBIGUOUS_RULE_TEXT` → Clarity Ticket opens automatically for the guideline owner while rules stay untouched.
6. **Single-Comma SHA-256 Tamper Climax**: Reviewer approves clean copy → green `SEALED — SHA-256: ...` badge. Change a single comma (or `"up to 8%"` → `"guaranteed 8%"`) and click **Verify Before Publish** → flips bright red **APPROVAL VOIDED — Post-Sign-Off Tampering Detected** with highlighted word diff.
