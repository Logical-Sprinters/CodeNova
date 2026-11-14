-- =============================================================================
-- BrandGuard · tests/001_assertions.sql
-- Behavioural assertions for the schema. They run inside one transaction and are
-- rolled back, so the suite is safe to run against a live demo database.
--
--   make db-test
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/tests/001_assertions.sql
--
-- Every assertion tests a claim the product makes to a user. If one fails, the
-- claim is false and the README is lying.
-- =============================================================================

\set ON_ERROR_STOP on
\pset pager off

BEGIN;
\o /dev/null

CREATE TEMP TABLE _results (n SERIAL, name TEXT, ok BOOLEAN);

CREATE OR REPLACE FUNCTION pg_temp.check(p_name TEXT, p_ok BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO _results (name, ok) VALUES (p_name, COALESCE(p_ok, FALSE));
    IF NOT COALESCE(p_ok, FALSE) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: %', p_name;
    END IF;
    RAISE NOTICE '  ok    %', p_name;
END;
$$;

-- Expect a statement to be rejected. Success here means the database refused.
CREATE OR REPLACE FUNCTION pg_temp.expect_rejection(p_name TEXT, p_sql TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        INSERT INTO _results (name, ok) VALUES (p_name, FALSE);
        RAISE EXCEPTION 'ASSERTION FAILED: % (the database accepted something it must refuse)', p_name;
    EXCEPTION
        WHEN check_violation OR unique_violation OR insufficient_privilege OR raise_exception THEN
            IF SQLERRM LIKE 'ASSERTION FAILED%' OR SQLERRM LIKE 'expected%' THEN
                RAISE;   -- our own failure marker, not the refusal we wanted
            END IF;
            INSERT INTO _results (name, ok) VALUES (p_name, TRUE);
            RAISE NOTICE '  ok    %  (correctly refused)', p_name;
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- A rule is live only inside its window and until something supersedes it
-- ---------------------------------------------------------------------------
SELECT pg_temp.check(
  'A01 superseded PRIC-001 is not live although its own window is still open',
  NOT EXISTS (SELECT 1 FROM live_rules_at(now()) WHERE rule_id = 'PRIC-001'));

SELECT pg_temp.check(
  'A02 PRIC-002 is live today',
  EXISTS (SELECT 1 FROM live_rules_at(now()) WHERE rule_id = 'PRIC-002' AND version = 1));

SELECT pg_temp.check(
  'A03 an ACTIVE row past its expiry date (PROMO-001) is not live',
  NOT EXISTS (SELECT 1 FROM live_rules_at(now()) WHERE rule_id = 'PROMO-001')
  AND EXISTS (SELECT 1 FROM rules WHERE rule_id = 'PROMO-001' AND status = 'ACTIVE'));

SELECT pg_temp.check(
  'A04 time travel: 100 days ago PRIC-001 was live and PRIC-002 was not',
  EXISTS (SELECT 1 FROM live_rules_at(now() - INTERVAL '100 days') WHERE rule_id = 'PRIC-001')
  AND NOT EXISTS (SELECT 1 FROM live_rules_at(now() - INTERVAL '100 days') WHERE rule_id = 'PRIC-002'));

SELECT pg_temp.check(
  'A05 an unconfirmed DRAFT rule (LEGL-001) is never live',
  NOT EXISTS (SELECT 1 FROM live_rules_at(now()) WHERE rule_id = 'LEGL-001'));

SELECT pg_temp.check(
  'A06 channel filtering respects the rules channels column',
  EXISTS (SELECT 1 FROM live_rules_for_channel('social') WHERE rule_id = 'TERM-001')
  AND NOT EXISTS (SELECT 1 FROM live_rules_for_channel('web') WHERE rule_id = 'PRIC-002'));

-- ---------------------------------------------------------------------------
-- The hash belongs to the database
-- ---------------------------------------------------------------------------
SELECT pg_temp.check(
  'A07 canonicalisation ignores spacing, so two renderings hash identically',
  canonicalise_text('  TaskFlow   Pro  ') = canonicalise_text('TaskFlow Pro')
  AND content_hash('TaskFlow Pro  ', 'social') = content_hash('TaskFlow Pro', 'social'));

SELECT pg_temp.check(
  'A08 the hash is a 64-character sha256 that depends on the channel',
  length(content_hash('same text', 'social')) = 64
  AND content_hash('same text', 'social') <> content_hash('same text', 'email'));

SELECT pg_temp.check(
  'A09 the seed inserted versions with a NULL hash and the trigger filled it',
  NOT EXISTS (SELECT 1 FROM content_versions WHERE canonical_hash IS NULL)
  AND (SELECT canonical_hash FROM content_versions
        WHERE content_version_id = 'b0000000-0000-4000-8000-000000000001')
      = content_hash((SELECT content_text FROM content_versions
                       WHERE content_version_id = 'b0000000-0000-4000-8000-000000000001'),
                     'social'));

SELECT pg_temp.expect_rejection(
  'A10 a supplied hash that does not match the text is refused', $$
    INSERT INTO content_versions (content_id, version_number, content_text, created_by, canonical_hash)
    VALUES ('c0000000-0000-4000-8000-000000000001', 900,
            'text that will not match the hash', '00000000-0000-4000-8000-000000000002',
            repeat('0', 64))
$$);

-- ---------------------------------------------------------------------------
-- Findings may not cite a rule that was not in force
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_rejection(
  'A11 a CONFIRMED finding cannot cite a superseded rule', $$
    INSERT INTO findings (check_run_id, status, rule_id, rule_version, evidence_quote, message, action)
    VALUES ('d0000000-0000-4000-8000-000000000001', 'CONFIRMED_RULE_MATCH', 'PRIC-001', 1,
            '$29', 'claims a rule that is no longer live', 'BLOCK_EXPORT')
$$);

INSERT INTO findings (check_run_id, status, rule_id, rule_version, evidence_quote, message, action)
VALUES ('d0000000-0000-4000-8000-000000000001', 'SOURCE_CONFLICT_OR_EXPIRED', 'PRIC-001', 1,
        '$29', 'the cited price rule has been superseded by PRIC-002', 'FLAG_REVIEW');

SELECT pg_temp.check(
  'A12 an expired-source finding was accepted and is stored',
  EXISTS (SELECT 1 FROM findings
           WHERE rule_id = 'PRIC-001' AND status = 'SOURCE_CONFLICT_OR_EXPIRED'));

-- ---------------------------------------------------------------------------
-- One accepted rewrite per finding
-- ---------------------------------------------------------------------------
UPDATE finding_rewrites SET accepted = TRUE, accepted_at = now()
 WHERE finding_id = 'e0000000-0000-4000-8000-000000000001' AND option_label = 'B';

SELECT pg_temp.expect_rejection(
  'A13 a second accepted rewrite for the same finding is refused', $$
    UPDATE finding_rewrites SET accepted = TRUE, accepted_at = now()
     WHERE finding_id = 'e0000000-0000-4000-8000-000000000001' AND option_label = 'A'
$$);

-- ---------------------------------------------------------------------------
-- Approval is bound to a version, a role, a person and a hash
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_rejection(
  'A14 a creator cannot approve', $$
    INSERT INTO approvals (content_id, content_version_id, state, content_hash, approved_by, approved_at)
    SELECT 'c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001',
           'APPROVED', canonical_hash, '00000000-0000-4000-8000-000000000002', now()
      FROM content_versions WHERE content_version_id = 'b0000000-0000-4000-8000-000000000001'
$$);

SELECT pg_temp.expect_rejection(
  'A15 a deactivated reviewer cannot approve', $$
    INSERT INTO approvals (content_id, content_version_id, state, content_hash, approved_by, approved_at)
    SELECT 'c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001',
           'APPROVED', canonical_hash, '00000000-0000-4000-8000-000000000004', now()
      FROM content_versions WHERE content_version_id = 'b0000000-0000-4000-8000-000000000001'
$$);

SELECT pg_temp.expect_rejection(
  'A16 the author of a version cannot approve it, even as an admin', $$
    INSERT INTO approvals (content_id, content_version_id, state, content_hash, approved_by, approved_at)
    SELECT 'c0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000003',
           'VOID', canonical_hash, '00000000-0000-4000-8000-000000000001', now()
      FROM content_versions WHERE content_version_id = 'b0000000-0000-4000-8000-000000000003'
$$);

SELECT pg_temp.expect_rejection(
  'A17 an approval carrying the wrong hash is refused', $$
    INSERT INTO approvals (content_id, content_version_id, state, content_hash, approved_by, approved_at)
    VALUES ('c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001',
            'APPROVED', repeat('a', 64), '00000000-0000-4000-8000-000000000003', now())
$$);

-- The honest approval, so the void test below has something to void.
INSERT INTO approvals (content_id, content_version_id, state, content_hash, approved_by, approved_at)
SELECT 'c0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000002',
       'APPROVED', canonical_hash, '00000000-0000-4000-8000-000000000003', now()
  FROM content_versions WHERE content_version_id = 'b0000000-0000-4000-8000-000000000002';

SELECT pg_temp.check(
  'A18 a reviewer may approve a version they did not write',
  (SELECT state FROM approvals WHERE content_version_id = 'b0000000-0000-4000-8000-000000000002') = 'APPROVED');

-- ---------------------------------------------------------------------------
-- The centrepiece: editing the copy voids the approval, and the database says so
-- ---------------------------------------------------------------------------
INSERT INTO content_versions (content_id, version_number, content_text, created_by)
VALUES ('c0000000-0000-4000-8000-000000000002', 2,
        'TaskFlow keeps every team on track. Start free.', '00000000-0000-4000-8000-000000000002');

SELECT pg_temp.check(
  'A19 the previous approval is now VOID',
  (SELECT state FROM approvals WHERE content_version_id = 'b0000000-0000-4000-8000-000000000002') = 'VOID');

SELECT pg_temp.check(
  'A20 the void carries the reason, the old hash and the new version number',
  (SELECT void_diff->>'new_version_number' FROM approvals
    WHERE content_version_id = 'b0000000-0000-4000-8000-000000000002') = '2'
  AND (SELECT void_reason FROM approvals
        WHERE content_version_id = 'b0000000-0000-4000-8000-000000000002') IS NOT NULL);

SELECT pg_temp.check(
  'A21 the audit log records the void as SYSTEM acting on its own',
  EXISTS (SELECT 1 FROM audit_log
           WHERE content_id = 'c0000000-0000-4000-8000-000000000002'
             AND action = 'voided' AND actor_type = 'SYSTEM' AND actor_id IS NULL));

-- ---------------------------------------------------------------------------
-- The audit log is append-only
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_rejection(
  'A22 an audit entry cannot be updated', $$
    UPDATE audit_log SET action = 'approved' WHERE entry_id = 'f0000000-0000-4000-8000-000000000001'
$$);

SELECT pg_temp.expect_rejection(
  'A23 an audit entry cannot be deleted', $$
    DELETE FROM audit_log WHERE entry_id = 'f0000000-0000-4000-8000-000000000001'
$$);

-- ---------------------------------------------------------------------------
-- Rule and override integrity
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_rejection(
  'A24 a price-sensitive rule must have an expiry date', $$
    INSERT INTO rules (rule_id, version, type, rule_text, source_file, status, effective_from,
                       channels, price_sensitive, confirmed_by)
    VALUES ('PRIC-999', 1, 'fact', 'A price with no end date.', 'x.pdf', 'DRAFT', current_date,
            ARRAY['social'], TRUE, '00000000-0000-4000-8000-000000000001')
$$);

SELECT pg_temp.expect_rejection(
  'A25 a rule cannot become ACTIVE without a confirming human', $$
    INSERT INTO rules (rule_id, version, type, rule_text, source_file, status, effective_from,
                       channels, confirmed_by)
    VALUES ('CLAI-999', 1, 'claim', 'An unconfirmed claim rule.', 'x.pdf', 'ACTIVE', current_date,
            ARRAY['social'], NULL)
$$);

SELECT pg_temp.expect_rejection(
  'A26 an override must carry a real reason', $$
    INSERT INTO overrides (finding_id, rule_id, rule_version, actor_id, actor_role, reason_text)
    VALUES ('e0000000-0000-4000-8000-000000000003', 'CLAI-001', 1,
            '00000000-0000-4000-8000-000000000002', 'creator', 'no')
$$);

INSERT INTO overrides (finding_id, rule_id, rule_version, actor_id, actor_role, reason_code, reason_text)
VALUES ('e0000000-0000-4000-8000-000000000003', 'CLAI-001', 1,
        '00000000-0000-4000-8000-000000000002', 'creator', 'approved_exception',
        'We hold a third-party ranking report the guidelines do not reference yet.');

SELECT pg_temp.check(
  'A27 an override is counted as a clarity ticket against its rule version',
  (SELECT override_count FROM v_clarity_tickets
    WHERE rule_id = 'CLAI-001' AND rule_version = 1) = 1);

DO $$
DECLARE
    v_expired INTEGER;
    v_status  rule_status;
BEGIN
    SELECT expired INTO v_expired FROM refresh_rule_lifecycle();
    SELECT status  INTO v_status  FROM rules WHERE rule_id = 'PROMO-001';
    PERFORM pg_temp.check(
        'A28 refresh_rule_lifecycle expires the drifted PROMO-001 row',
        v_expired >= 1 AND v_status = 'EXPIRED');
END;
$$;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_total   INTEGER;
    v_passed  INTEGER;
    v_failed  INTEGER;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok)
      INTO v_total, v_passed, v_failed FROM _results;

    RAISE NOTICE '';
    RAISE NOTICE '--------------------------------------------------------';
    RAISE NOTICE 'BrandGuard schema assertions: % of % passed', v_passed, v_total;
    RAISE NOTICE '--------------------------------------------------------';
    IF v_failed > 0 THEN
        RAISE EXCEPTION '% assertion(s) failed', v_failed;
    END IF;
    RAISE NOTICE 'All assertions passed. Every change above was rolled back.';
END;
$$;

ROLLBACK;
\o
