CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TYPE user_role AS ENUM ('admin', 'creator', 'reviewer');
CREATE TYPE rule_type AS ENUM ('fact', 'term', 'tone', 'claim', 'visual');
CREATE TYPE rule_status AS ENUM ('DRAFT', 'ACTIVE', 'SUPERSEDED', 'EXPIRED');
CREATE TYPE risk_tier AS ENUM ('standard', 'high');
CREATE TYPE finding_status AS ENUM (
    'CONFIRMED_RULE_MATCH',
    'AI_INTERPRETATION',
    'UNSUPPORTED',
    'SOURCE_CONFLICT_OR_EXPIRED',
    'NEEDS_AUTHORISED_REVIEWER'
);
CREATE TYPE system_action AS ENUM (
    'BLOCK_EXPORT',
    'ADVISORY',
    'FLAG_REVIEW',
    'ESCALATE_ADMIN',
    'ROUTE_LEGAL'
);
CREATE TYPE approval_state AS ENUM (
    'DRAFT',
    'CHECKS_RUN',
    'IN_REVIEW',
    'APPROVED',
    'VOID'
);
CREATE TYPE check_outcome AS ENUM ('RUNNING', 'COMPLETED', 'ABSTAINED', 'FAILED');
CREATE TYPE audit_actor_type AS ENUM ('USER', 'SYSTEM');
CREATE TYPE audit_action AS ENUM (
    'submitted',
    'checked',
    'edited',
    'overridden',
    'approved',
    'voided'
);

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
    role user_role NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE content_items (
    content_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES users(user_id),
    channel TEXT NOT NULL CHECK (length(trim(channel)) > 0),
    publish_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rules (
    rule_id TEXT NOT NULL CHECK (length(trim(rule_id)) > 0),
    version INTEGER NOT NULL CHECK (version > 0),
    type rule_type NOT NULL,
    rule_text TEXT NOT NULL CHECK (length(trim(rule_text)) > 0),
    source_file TEXT NOT NULL CHECK (length(trim(source_file)) > 0),
    source_page INTEGER CHECK (source_page IS NULL OR source_page > 0),
    status rule_status NOT NULL DEFAULT 'DRAFT',
    effective_from DATE NOT NULL,
    expires_on DATE,
    supersedes_rule_id TEXT,
    supersedes_version INTEGER,
    risk_tier risk_tier NOT NULL DEFAULT 'standard',
    channels TEXT[] NOT NULL CHECK (cardinality(channels) > 0),
    confirmed_by UUID REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (rule_id, version),
    FOREIGN KEY (supersedes_rule_id, supersedes_version)
        REFERENCES rules(rule_id, version),
    CHECK (expires_on IS NULL OR expires_on >= effective_from),
    CHECK (
        (supersedes_rule_id IS NULL AND supersedes_version IS NULL)
        OR (supersedes_rule_id IS NOT NULL AND supersedes_version IS NOT NULL)
    ),
    CHECK (supersedes_rule_id IS NULL OR supersedes_rule_id <> rule_id),
    CHECK (status <> 'ACTIVE' OR confirmed_by IS NOT NULL)
);

CREATE INDEX rules_active_channels_idx
    ON rules USING GIN (channels)
    WHERE status = 'ACTIVE';

CREATE TABLE content_versions (
    content_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL REFERENCES content_items(content_id),
    version_number INTEGER NOT NULL CHECK (version_number > 0),
    content_text TEXT NOT NULL,
    asset_fingerprints TEXT[] NOT NULL DEFAULT '{}',
    canonical_hash CHAR(64) NOT NULL
        CHECK (canonical_hash ~ '^[0-9a-f]{64}$'),
    created_by UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (content_id, version_number),
    UNIQUE (content_version_id, content_id)
);

CREATE TABLE check_runs (
    check_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_version_id UUID NOT NULL
        REFERENCES content_versions(content_version_id),
    outcome check_outcome NOT NULL DEFAULT 'RUNNING',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    CHECK (completed_at IS NULL OR completed_at >= started_at),
    CHECK (
        (outcome = 'RUNNING' AND completed_at IS NULL)
        OR (outcome <> 'RUNNING' AND completed_at IS NOT NULL)
    )
);

CREATE INDEX check_runs_version_idx ON check_runs(content_version_id);

CREATE TABLE processing_receipts (
    receipt_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    check_run_id UUID NOT NULL UNIQUE REFERENCES check_runs(check_run_id),
    sent_text TEXT NOT NULL,
    redactions JSONB NOT NULL DEFAULT '[]'::jsonb
        CHECK (jsonb_typeof(redactions) = 'array'),
    retention_terms TEXT NOT NULL CHECK (length(trim(retention_terms)) > 0),
    provider TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE processing_receipt_rules (
    check_run_id UUID NOT NULL REFERENCES processing_receipts(check_run_id),
    rule_id TEXT NOT NULL,
    rule_version INTEGER NOT NULL,
    PRIMARY KEY (check_run_id, rule_id, rule_version),
    FOREIGN KEY (rule_id, rule_version)
        REFERENCES rules(rule_id, version)
);

CREATE TABLE findings (
    finding_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    check_run_id UUID NOT NULL REFERENCES check_runs(check_run_id),
    status finding_status NOT NULL,
    rule_id TEXT NOT NULL,
    rule_version INTEGER NOT NULL,
    evidence_quote TEXT NOT NULL CHECK (length(trim(evidence_quote)) > 0),
    span_start INTEGER,
    span_end INTEGER,
    message TEXT NOT NULL CHECK (length(trim(message)) > 0),
    suggested_fix TEXT,
    action system_action NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (rule_id, rule_version)
        REFERENCES rules(rule_id, version),
    CHECK (
        (span_start IS NULL AND span_end IS NULL)
        OR (
            span_start IS NOT NULL
            AND span_end IS NOT NULL
            AND span_start >= 0
            AND span_end > span_start
        )
    )
);

CREATE INDEX findings_check_run_idx ON findings(check_run_id);

CREATE TABLE approval_records (
    approval_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL,
    content_version_id UUID NOT NULL,
    state approval_state NOT NULL DEFAULT 'DRAFT',
    content_hash CHAR(64) NOT NULL
        CHECK (content_hash ~ '^[0-9a-f]{64}$'),
    approved_by UUID REFERENCES users(user_id),
    approved_at TIMESTAMPTZ,
    voided_at TIMESTAMPTZ,
    void_diff JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (content_version_id),
    FOREIGN KEY (content_version_id, content_id)
        REFERENCES content_versions(content_version_id, content_id),
    CHECK (
        state NOT IN ('APPROVED', 'VOID')
        OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CHECK (
        (state = 'VOID' AND voided_at IS NOT NULL)
        OR (state <> 'VOID' AND voided_at IS NULL)
    )
);

CREATE TABLE audit_log (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL REFERENCES content_items(content_id),
    actor_type audit_actor_type NOT NULL,
    actor_id UUID REFERENCES users(user_id),
    action audit_action NOT NULL,
    reason TEXT,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (actor_type = 'USER' AND actor_id IS NOT NULL)
        OR (actor_type = 'SYSTEM' AND actor_id IS NULL)
    ),
    CHECK (
        action <> 'overridden'
        OR (reason IS NOT NULL AND length(trim(reason)) > 0)
    )
);

CREATE INDEX audit_log_content_time_idx
    ON audit_log(content_id, occurred_at DESC);

CREATE FUNCTION reject_immutable_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION '% does not allow mutation', TG_TABLE_NAME;
END;
$$;

CREATE TRIGGER content_versions_no_update_delete
BEFORE UPDATE OR DELETE ON content_versions
FOR EACH ROW EXECUTE FUNCTION reject_immutable_mutation();

CREATE TRIGGER content_versions_no_truncate
BEFORE TRUNCATE ON content_versions
FOR EACH STATEMENT EXECUTE FUNCTION reject_immutable_mutation();

CREATE TRIGGER audit_log_no_update_delete
BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION reject_immutable_mutation();

CREATE TRIGGER audit_log_no_truncate
BEFORE TRUNCATE ON audit_log
FOR EACH STATEMENT EXECUTE FUNCTION reject_immutable_mutation();

CREATE FUNCTION validate_approval_record()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    content_creator UUID;
    version_hash CHAR(64);
    reviewer_role user_role;
    reviewer_active BOOLEAN;
BEGIN
    SELECT creator_id
      INTO content_creator
      FROM content_items
     WHERE content_id = NEW.content_id;

    SELECT canonical_hash
      INTO version_hash
      FROM content_versions
     WHERE content_version_id = NEW.content_version_id
       AND content_id = NEW.content_id;

    IF NEW.content_hash IS DISTINCT FROM version_hash THEN
        RAISE EXCEPTION 'approval hash must match the content version hash';
    END IF;

    IF NEW.state = 'APPROVED' THEN
        SELECT role, is_active
          INTO reviewer_role, reviewer_active
          FROM users
         WHERE user_id = NEW.approved_by;

        IF reviewer_role IS DISTINCT FROM 'reviewer'::user_role
           OR reviewer_active IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'approval requires an active reviewer';
        END IF;
    END IF;

    IF NEW.state IN ('APPROVED', 'VOID') AND NEW.approved_by IS NOT NULL
       AND NEW.approved_by = content_creator THEN
        RAISE EXCEPTION 'a creator cannot approve their own content';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER approval_record_validate
BEFORE INSERT OR UPDATE ON approval_records
FOR EACH ROW EXECUTE FUNCTION validate_approval_record();
