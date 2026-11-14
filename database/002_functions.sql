-- =============================================================================
-- BrandGuard · 002_functions.sql
-- Behaviour that belongs to the database because a promise in application code
-- is not a guarantee. Run after 001_schema.sql.
--
-- Six things are enforced here:
--   1. the content hash is computed, never supplied
--   2. a new version voids the previous approval, and says so in the audit log
--   3. a finding may not cite a rule that was not live when the check ran
--   4. an approval requires an active reviewer who is not the author
--   5. a rule is live only inside its window and until something supersedes it
--   6. the audit log cannot be rewritten
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Canonical form and content hash.
--    Same text, same hash — regardless of trailing spaces, curly quotes typed as
--    curly quotes, or the order of asset fingerprints.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION canonicalise_text(p_text TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE STRICT
AS $$
    SELECT btrim(regexp_replace(
        replace(replace(normalize(p_text, NFKC), chr(65279), ''), chr(8203), ''),
        '\s+', ' ', 'g'));
$$;

CREATE OR REPLACE FUNCTION content_hash(
    p_text         TEXT,
    p_channel      TEXT,
    p_fingerprints TEXT[] DEFAULT '{}'
)
RETURNS CHAR(64)
LANGUAGE sql IMMUTABLE STRICT
AS $$
    SELECT encode(
             digest(
               'brandguard/v1' || chr(31) ||
               canonicalise_text(p_text) || chr(31) ||
               p_channel || chr(31) ||
               array_to_string(ARRAY(SELECT unnest(p_fingerprints) ORDER BY 1), ','),
               'sha256'),
             'hex');
$$;

CREATE OR REPLACE FUNCTION content_version_set_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_channel  TEXT;
    v_computed CHAR(64);
BEGIN
    SELECT channel INTO v_channel FROM content_items WHERE content_id = NEW.content_id;
    v_computed := content_hash(NEW.content_text, v_channel, NEW.asset_fingerprints);

    IF NEW.canonical_hash IS NULL THEN
        NEW.canonical_hash := v_computed;
    ELSIF NEW.canonical_hash <> v_computed THEN
        RAISE EXCEPTION
            'canonical_hash does not match the text (given %, computed %)',
            NEW.canonical_hash, v_computed
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER content_versions_set_hash
    BEFORE INSERT ON content_versions
    FOR EACH ROW EXECUTE FUNCTION content_version_set_hash();

-- ---------------------------------------------------------------------------
-- 2. A new version voids the standing approval.
--    This is the product's central claim, and it lives here so that no route,
--    script or future contributor can forget to call it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION void_prior_approvals()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    UPDATE approvals
       SET state       = 'VOID',
           voided_at   = now(),
           void_reason = 'a new content version was created',
           void_diff   = jsonb_build_object(
                             'previous_state',     state,
                             'previous_hash',      content_hash,
                             'new_version_number', NEW.version_number,
                             'new_version_id',     NEW.content_version_id)
     WHERE content_id = NEW.content_id
       AND content_version_id <> NEW.content_version_id
       AND state = 'APPROVED';

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count > 0 THEN
        INSERT INTO audit_log (content_id, actor_type, actor_id, action, reason, details)
        VALUES (NEW.content_id, 'SYSTEM', NULL, 'voided',
                'a new content version was created',
                jsonb_build_object('voided_approvals',    v_count,
                                   'new_version_number',  NEW.version_number,
                                   'new_version_id',      NEW.content_version_id));
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER content_versions_void_prior
    AFTER INSERT ON content_versions
    FOR EACH ROW EXECUTE FUNCTION void_prior_approvals();

-- ---------------------------------------------------------------------------
-- 3. What is live at a moment in time.
--    Not "WHERE status = 'ACTIVE'". That lies the moment a row drifts: an ACTIVE
--    rule whose expires_on has passed, or one already replaced by a successor
--    that is itself in force.
--    Note it also does not simply filter on the current status column, because
--    status is today's truth: a rule marked SUPERSEDED last week was live last
--    month, and a finding from last month must still be judged honestly.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION live_rules_at(p_at TIMESTAMPTZ DEFAULT now())
RETURNS SETOF rules
LANGUAGE sql STABLE
AS $$
    SELECT r.*
    FROM rules r
    WHERE r.status <> 'DRAFT'
      AND r.effective_from <= p_at::date
      AND (r.expires_on IS NULL OR p_at::date <= r.expires_on)
      AND NOT EXISTS (
            SELECT 1
            FROM rules successor
            WHERE successor.supersedes_rule_id = r.rule_id
              AND successor.supersedes_version = r.version
              AND successor.status <> 'DRAFT'
              AND successor.effective_from <= p_at::date
      );
$$;

CREATE OR REPLACE VIEW v_live_rules AS
    SELECT * FROM live_rules_at(now());

CREATE OR REPLACE FUNCTION live_rules_for_channel(
    p_channel TEXT,
    p_at      TIMESTAMPTZ DEFAULT now()
)
RETURNS SETOF rules
LANGUAGE sql STABLE
AS $$
    SELECT *
    FROM live_rules_at(p_at) r
    WHERE p_channel = ANY (r.channels)
    ORDER BY (r.risk_tier = 'high') DESC, r.type, r.rule_id;
$$;

-- Keep the status column honest when a date simply passes.
CREATE OR REPLACE FUNCTION refresh_rule_lifecycle()
RETURNS TABLE (expired INTEGER, superseded INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_expired    INTEGER := 0;
    v_superseded INTEGER := 0;
BEGIN
    UPDATE rules SET status = 'EXPIRED'
     WHERE status = 'ACTIVE'
       AND expires_on IS NOT NULL
       AND expires_on < current_date;
    GET DIAGNOSTICS v_expired = ROW_COUNT;

    UPDATE rules r SET status = 'SUPERSEDED'
     WHERE r.status = 'ACTIVE'
       AND EXISTS (
             SELECT 1 FROM rules s
             WHERE s.supersedes_rule_id = r.rule_id
               AND s.supersedes_version = r.version
               AND s.status = 'ACTIVE'
               AND s.effective_from <= current_date);
    GET DIAGNOSTICS v_superseded = ROW_COUNT;

    RETURN QUERY SELECT v_expired, v_superseded;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. A finding may only claim a confirmed rule match if that rule was live
--    when the check ran. Without this, a finding is decoration.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION finding_requires_live_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_started TIMESTAMPTZ;
    v_live    INTEGER;
BEGIN
    IF NEW.status <> 'CONFIRMED_RULE_MATCH' THEN
        RETURN NEW;
    END IF;

    SELECT started_at INTO v_started
      FROM check_runs WHERE check_run_id = NEW.check_run_id;

    SELECT count(*) INTO v_live
      FROM live_rules_at(COALESCE(v_started, now())) r
     WHERE r.rule_id = NEW.rule_id
       AND r.version = NEW.rule_version;

    IF v_live = 0 THEN
        RAISE EXCEPTION
            'finding cites % v% as a confirmed match, but that version was not live at check time; use SOURCE_CONFLICT_OR_EXPIRED',
            NEW.rule_id, NEW.rule_version
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER findings_require_live_rule
    BEFORE INSERT ON findings
    FOR EACH ROW EXECUTE FUNCTION finding_requires_live_rule();

-- ---------------------------------------------------------------------------
-- 5. An approval needs an active reviewer, who is not the author of the version,
--    and it must carry the hash of that version — not a hash of its own choosing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION approvals_require_authorised_reviewer()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_role     user_role;
    v_active   BOOLEAN;
    v_author   UUID;
    v_hash     CHAR(64);
BEGIN
    IF NEW.state <> 'APPROVED' THEN
        RETURN NEW;
    END IF;

    SELECT role, is_active INTO v_role, v_active
      FROM users WHERE user_id = NEW.approved_by;

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'approved_by % is not a known user', NEW.approved_by
            USING ERRCODE = 'check_violation';
    END IF;

    IF NOT v_active THEN
        RAISE EXCEPTION 'user % is deactivated and cannot approve', NEW.approved_by
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_role NOT IN ('reviewer', 'admin') THEN
        RAISE EXCEPTION 'user % has role %, which cannot approve', NEW.approved_by, v_role
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT created_by, canonical_hash INTO v_author, v_hash
      FROM content_versions WHERE content_version_id = NEW.content_version_id;

    IF v_author = NEW.approved_by THEN
        RAISE EXCEPTION 'the author of a version cannot approve it'
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.content_hash <> v_hash THEN
        RAISE EXCEPTION 'approval hash does not match the approved version'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER approvals_require_reviewer
    BEFORE INSERT OR UPDATE ON approvals
    FOR EACH ROW EXECUTE FUNCTION approvals_require_authorised_reviewer();

-- ---------------------------------------------------------------------------
-- 6. The audit log cannot be rewritten. Append-only is a schema property here,
--    not a convention that a future contributor might not read.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_log_is_append_only()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

CREATE TRIGGER audit_log_no_update
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_is_append_only();

-- ---------------------------------------------------------------------------
-- Convenience: the third differentiator as a query. Rules that keep being
-- overruled are rules that are wrong, and this is how the team finds out.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_clarity_tickets AS
    SELECT o.rule_id,
           o.rule_version,
           count(*)                             AS override_count,
           count(DISTINCT o.actor_id)           AS distinct_people,
           max(o.created_at)                    AS last_raised_at,
           (array_agg(o.reason_code ORDER BY o.created_at DESC))[1] AS latest_reason_code,
           (array_agg(o.reason_text ORDER BY o.created_at DESC))[1] AS latest_reason
    FROM overrides o
    GROUP BY o.rule_id, o.rule_version
    HAVING count(*) >= 1
    ORDER BY count(*) DESC;

-- Keep content_items.updated_at honest without application help.
CREATE OR REPLACE FUNCTION touch_content_item()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE content_items SET updated_at = now() WHERE content_id = NEW.content_id;
    RETURN NULL;
END;
$$;

CREATE TRIGGER content_versions_touch_item
    AFTER INSERT ON content_versions
    FOR EACH ROW EXECUTE FUNCTION touch_content_item();
