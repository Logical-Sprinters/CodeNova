-- =============================================================================
-- BrandGuard · 001_schema.sql
-- Core relational model. Run first, then 002_functions.sql, then 003_seed.sql.
-- Target: PostgreSQL 16. Nothing here depends on pgvector or a language model.
--
-- The design principle behind every table below: an approval must be impossible
-- to fake, and a finding must be impossible to credit to a rule that was not in
-- force. Constraints do that; application code is only a convenience layer.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Enumerated domains. Enums, not free text: a typo in a status should be a
-- migration, not a finding that quietly disappears from a filter.
-- ---------------------------------------------------------------------------
CREATE TYPE user_role AS ENUM ('admin', 'creator', 'reviewer');

CREATE TYPE rule_type AS ENUM ('fact', 'term', 'tone', 'claim', 'visual');

CREATE TYPE rule_status AS ENUM ('DRAFT', 'ACTIVE', 'SUPERSEDED', 'EXPIRED');

CREATE TYPE risk_tier AS ENUM ('standard', 'high');

-- The five finding statuses are the product's vocabulary. Each one is a distinct
-- claim about the world, and only the first two may block an approval:
--   CONFIRMED_RULE_MATCH        a named, live rule is broken. Deterministic.
--   SOURCE_CONFLICT_OR_EXPIRED  the rule set contradicts itself, or the source
--                               lapsed, so no honest answer exists. Do not guess.
--   NEEDS_AUTHORISED_REVIEWER   a person must decide; a rule cannot.
--   AI_INTERPRETATION           our reading of the copy, labelled as our reading.
--   UNSUPPORTED                 nothing backs this claim. Not proof it is false.
CREATE TYPE finding_status AS ENUM (
    'CONFIRMED_RULE_MATCH',
    'AI_INTERPRETATION',
    'UNSUPPORTED',
    'SOURCE_CONFLICT_OR_EXPIRED',
    'NEEDS_AUTHORISED_REVIEWER'
);

-- What the system asks the workflow to do about a finding.
CREATE TYPE system_action AS ENUM (
    'BLOCK_EXPORT', 'ADVISORY', 'FLAG_REVIEW', 'ESCALATE_ADMIN', 'ROUTE_LEGAL'
);

CREATE TYPE approval_state AS ENUM ('DRAFT', 'CHECKS_RUN', 'IN_REVIEW', 'APPROVED', 'VOID');

CREATE TYPE check_outcome AS ENUM ('RUNNING', 'COMPLETED', 'ABSTAINED', 'FAILED');

CREATE TYPE audit_actor_type AS ENUM ('USER', 'SYSTEM');

CREATE TYPE audit_action AS ENUM (
    'submitted', 'checked', 'edited', 'overridden', 'approved', 'voided'
);

CREATE TYPE document_status AS ENUM ('DRAFT', 'ACTIVE', 'SUPERSEDED', 'EXPIRED');

-- ---------------------------------------------------------------------------
-- users — who may act, and in which capacity. No passwords: authentication is
-- out of scope for this build and faking it would be worse than omitting it.
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    user_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name TEXT NOT NULL CHECK (length(btrim(display_name)) > 0),
    email        TEXT NOT NULL UNIQUE CHECK (position('@' IN email) > 1),
    role         user_role NOT NULL,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON COLUMN users.is_active IS
    'A deactivated account must not be able to approve. Enforced in the approval trigger.';

-- ---------------------------------------------------------------------------
-- guideline_documents — where rules come from. A rule without a source document
-- is an opinion; the whole product rests on being able to show the page.
-- ---------------------------------------------------------------------------
CREATE TABLE guideline_documents (
    document_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL CHECK (length(btrim(title)) > 0),
    version_label   TEXT NOT NULL CHECK (length(btrim(version_label)) > 0),
    doc_type        TEXT NOT NULL DEFAULT 'markdown'
                        CHECK (doc_type IN ('markdown', 'pdf', 'docx', 'url')),
    status          document_status NOT NULL DEFAULT 'DRAFT',
    effective_from  DATE,
    expires_on      DATE,
    file_name       TEXT,
    page_count      INTEGER CHECK (page_count IS NULL OR page_count > 0),
    checksum_sha256 CHAR(64) CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    supersedes_id   UUID REFERENCES guideline_documents(document_id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (title, version_label),
    CHECK (expires_on IS NULL OR effective_from IS NULL OR expires_on >= effective_from)
);

-- ---------------------------------------------------------------------------
-- rules — versioned, dated, and independently confirmable.
-- (rule_id, version) is the identity of a rule. A rule is never edited in place:
-- a correction is a new version that supersedes the old one, so any historical
-- finding still points at the exact text it was judged against.
-- ---------------------------------------------------------------------------
CREATE TABLE rules (
    rule_id           TEXT NOT NULL CHECK (length(btrim(rule_id)) > 0),
    version           INTEGER NOT NULL CHECK (version > 0),
    type              rule_type NOT NULL,
    rule_text         TEXT NOT NULL CHECK (length(btrim(rule_text)) > 0),
    document_id       UUID REFERENCES guideline_documents(document_id),
    source_file       TEXT NOT NULL CHECK (length(btrim(source_file)) > 0),
    source_page       INTEGER CHECK (source_page IS NULL OR source_page > 0),
    status            rule_status NOT NULL DEFAULT 'DRAFT',
    effective_from    DATE NOT NULL,
    expires_on        DATE,
    supersedes_rule_id    TEXT,
    supersedes_version    INTEGER,
    risk_tier         risk_tier NOT NULL DEFAULT 'standard',
    channels          TEXT[] NOT NULL CHECK (cardinality(channels) > 0),
    price_sensitive   BOOLEAN NOT NULL DEFAULT FALSE,
    confirmed_by      UUID REFERENCES users(user_id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (rule_id, version),
    FOREIGN KEY (supersedes_rule_id, supersedes_version)
        REFERENCES rules(rule_id, version),

    CHECK (expires_on IS NULL OR expires_on >= effective_from),
    -- both halves of the supersession pointer, or neither
    CHECK ((supersedes_rule_id IS NULL) = (supersedes_version IS NULL)),
    CHECK (supersedes_rule_id IS NULL OR supersedes_rule_id <> rule_id),
    -- nothing reaches ACTIVE without a named human behind it
    CHECK (status <> 'ACTIVE' OR confirmed_by IS NOT NULL),
    -- a price rule that never expires is a price that can never be checked again
    CHECK (NOT price_sensitive OR expires_on IS NOT NULL)
);

CREATE INDEX rules_rule_id_idx ON rules (rule_id);
CREATE INDEX rules_live_idx ON rules (status, effective_from, expires_on);

COMMENT ON TABLE rules IS
    'Versioned guidance. Live means: status ACTIVE, inside [effective_from, expires_on], '
    'and not yet replaced by a live successor. live_rules_at() is the only correct way to ask.';

-- ---------------------------------------------------------------------------
-- content — an item (the thing being published) and its immutable versions.
-- The version is the unit of approval. Text is never overwritten.
-- ---------------------------------------------------------------------------
CREATE TABLE content_items (
    content_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id   UUID NOT NULL REFERENCES users(user_id),
    title        TEXT,
    channel      TEXT NOT NULL CHECK (length(btrim(channel)) > 0),
    publish_date DATE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE content_versions (
    content_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id         UUID NOT NULL REFERENCES content_items(content_id) ON DELETE CASCADE,
    version_number     INTEGER NOT NULL CHECK (version_number > 0),
    content_text       TEXT NOT NULL,
    asset_fingerprints TEXT[] NOT NULL DEFAULT '{}',
    canonical_hash     CHAR(64) NOT NULL CHECK (canonical_hash ~ '^[0-9a-f]{64}$'),
    created_by         UUID NOT NULL REFERENCES users(user_id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (content_id, version_number),
    UNIQUE (content_version_id, content_id)
);

CREATE INDEX content_versions_content_idx ON content_versions (content_id, version_number DESC);

COMMENT ON COLUMN content_versions.canonical_hash IS
    'Computed by a BEFORE INSERT trigger from the text, the channel and the asset '
    'fingerprints. Callers may not supply a different value: the trigger raises.';

-- ---------------------------------------------------------------------------
-- check_runs — one attempt to judge one version. Time is recorded because a
-- finding is only valid against the rules that were live at that moment.
-- ---------------------------------------------------------------------------
CREATE TABLE check_runs (
    check_run_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_version_id UUID NOT NULL REFERENCES content_versions(content_version_id) ON DELETE CASCADE,
    outcome            check_outcome NOT NULL DEFAULT 'RUNNING',
    started_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at       TIMESTAMPTZ,

    CHECK (completed_at IS NULL OR completed_at >= started_at),
    CHECK ((outcome = 'RUNNING') = (completed_at IS NULL))
);

CREATE INDEX check_runs_version_idx ON check_runs (content_version_id, started_at DESC);

-- ---------------------------------------------------------------------------
-- findings — one claim about one span of one version, tied to one rule version.
-- ---------------------------------------------------------------------------
CREATE TABLE findings (
    finding_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    check_run_id   UUID NOT NULL REFERENCES check_runs(check_run_id) ON DELETE CASCADE,
    status         finding_status NOT NULL,
    rule_id        TEXT NOT NULL,
    rule_version   INTEGER NOT NULL,
    evidence_quote TEXT NOT NULL CHECK (length(btrim(evidence_quote)) > 0),
    span_start     INTEGER,
    span_end       INTEGER,
    message        TEXT NOT NULL CHECK (length(btrim(message)) > 0),
    action         system_action NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    FOREIGN KEY (rule_id, rule_version) REFERENCES rules(rule_id, version),
    CHECK ((span_start IS NULL) = (span_end IS NULL)),
    CHECK (span_start IS NULL OR (span_start >= 0 AND span_end > span_start))
);

CREATE INDEX findings_run_idx ON findings (check_run_id);
CREATE INDEX findings_rule_idx ON findings (rule_id, rule_version);

-- ---------------------------------------------------------------------------
-- finding_rewrites — three different repairs for the same problem, because
-- "fix it" is not advice. Exactly one may be accepted per finding.
-- ---------------------------------------------------------------------------
CREATE TABLE finding_rewrites (
    rewrite_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    finding_id   UUID NOT NULL REFERENCES findings(finding_id) ON DELETE CASCADE,
    option_label TEXT NOT NULL CHECK (option_label IN ('A', 'B', 'C')),
    strategy     TEXT NOT NULL
                    CHECK (strategy IN ('surgical', 'brand_balanced', 'channel_native')),
    rewrite_text TEXT NOT NULL CHECK (length(btrim(rewrite_text)) > 0),
    accepted     BOOLEAN NOT NULL DEFAULT FALSE,
    accepted_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (finding_id, option_label),
    UNIQUE (finding_id, strategy),
    CHECK (NOT accepted OR accepted_at IS NOT NULL)
);

CREATE UNIQUE INDEX finding_rewrites_one_accepted
    ON finding_rewrites (finding_id) WHERE accepted;

-- ---------------------------------------------------------------------------
-- approvals — the heart of the product. One approval per content version,
-- carrying the hash of the text that was approved. Because a new version is a
-- new row, an old approval can only be invalidated, never quietly reused.
-- ---------------------------------------------------------------------------
CREATE TABLE approvals (
    approval_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id         UUID NOT NULL,
    content_version_id UUID NOT NULL,
    state              approval_state NOT NULL DEFAULT 'DRAFT',
    content_hash       CHAR(64) NOT NULL CHECK (content_hash ~ '^[0-9a-f]{64}$'),
    approved_by        UUID REFERENCES users(user_id),
    approved_at        TIMESTAMPTZ,
    voided_at          TIMESTAMPTZ,
    void_reason        TEXT,
    void_diff          JSONB,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (content_version_id),
    FOREIGN KEY (content_version_id, content_id)
        REFERENCES content_versions(content_version_id, content_id),

    CHECK (state NOT IN ('APPROVED', 'VOID')
           OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CHECK ((state = 'VOID') = (voided_at IS NOT NULL))
);

CREATE INDEX approvals_content_idx ON approvals (content_id, created_at DESC);

COMMENT ON TABLE approvals IS
    'Not append-only. Instead: each row is bound to one immutable version and hash, '
    'a new version voids it, and the void is written to audit_log by the database.';

-- ---------------------------------------------------------------------------
-- overrides — the third differentiator. When a person overrules a finding they
-- must say why, and the reason is kept against the rule version that caused it,
-- so a rule that is wrong again and again becomes visible as a number.
-- ---------------------------------------------------------------------------
CREATE TABLE overrides (
    override_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    finding_id   UUID NOT NULL UNIQUE REFERENCES findings(finding_id) ON DELETE CASCADE,
    rule_id      TEXT NOT NULL,
    rule_version INTEGER NOT NULL,
    actor_id     UUID NOT NULL REFERENCES users(user_id),
    actor_role   user_role NOT NULL,
    reason_code  TEXT NOT NULL DEFAULT 'rule_unclear'
                    CHECK (reason_code IN ('rule_unclear', 'not_applicable',
                                           'approved_exception', 'source_outdated')),
    reason_text  TEXT NOT NULL CHECK (length(btrim(reason_text)) >= 3),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    FOREIGN KEY (rule_id, rule_version) REFERENCES rules(rule_id, version)
);

-- ---------------------------------------------------------------------------
-- audit_log — append-only. A USER row means a person acted; a SYSTEM row means
-- the database acted because an invariant required it. Nothing here is ever
-- updated or deleted, and that is enforced by a trigger in 002_functions.sql.
-- ---------------------------------------------------------------------------
CREATE TABLE audit_log (
    entry_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id  UUID NOT NULL REFERENCES content_items(content_id) ON DELETE CASCADE,
    actor_type  audit_actor_type NOT NULL,
    actor_id    UUID REFERENCES users(user_id),
    action      audit_action NOT NULL,
    reason      TEXT,
    details     JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CHECK ((actor_type = 'USER' AND actor_id IS NOT NULL)
           OR (actor_type = 'SYSTEM' AND actor_id IS NULL)),
    CHECK (action <> 'overridden' OR (reason IS NOT NULL AND length(btrim(reason)) > 0))
);

CREATE INDEX audit_log_content_idx ON audit_log (content_id, occurred_at DESC);
CREATE INDEX audit_log_recent_idx ON audit_log (occurred_at DESC);
