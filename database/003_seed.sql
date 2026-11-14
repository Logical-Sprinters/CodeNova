-- =============================================================================
-- BrandGuard · 003_seed.sql
-- The demo world. Idempotent: re-running does not duplicate anything.
--
-- Every date is relative to CURRENT_DATE. A demo that only works in April is not
-- a demo, and hard-coded dates are the single most common reason a live run
-- shows "no live rules" on someone else's laptop.
--
-- The story this seed tells:
--   PRIC-001 said $29 and was superseded by PRIC-002 ($34) on day -30.
--   PRIC-001's own window still runs to day +90, so "WHERE status = 'ACTIVE'"
--   and "inside the window" both still match it. Only live_rules_at() knows
--   the truth, which is what the check engine uses.
--   PROMO-001 is ACTIVE in the column but expired in reality — the drift that
--   refresh_rule_lifecycle() exists to clean up.
--   TONE-001 and TONE-002 are both live and directly contradict each other:
--   the honest answer is "a human must decide", never a coin flip.
--   LEGL-001 is a DRAFT with no confirmed_by: it must never be cited.
-- =============================================================================

BEGIN;

INSERT INTO users (user_id, display_name, email, role, is_active) VALUES
  ('00000000-0000-4000-8000-000000000001', 'Priya Raman',   'priya@taskflow.example',  'admin',    TRUE),
  ('00000000-0000-4000-8000-000000000002', 'Arun Mehta',    'arun@agency.example',     'creator',  TRUE),
  ('00000000-0000-4000-8000-000000000003', 'Neha Kulkarni', 'neha@taskflow.example',   'reviewer', TRUE),
  ('00000000-0000-4000-8000-000000000004', 'Vikram Shah',   'vikram@taskflow.example', 'reviewer', FALSE)
ON CONFLICT (user_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Source documents
-- ---------------------------------------------------------------------------
INSERT INTO guideline_documents
  (document_id, title, version_label, doc_type, status, effective_from, file_name, page_count, checksum_sha256)
VALUES
  ('a0000000-0000-4000-8000-000000000001', 'TaskFlow Price Sheet',     '2026-Q1', 'pdf', 'SUPERSEDED',
   CURRENT_DATE - 200, 'taskflow-price-sheet-2026-Q1.pdf', 3,
   '3b1f2a4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708'),
  ('a0000000-0000-4000-8000-000000000002', 'TaskFlow Price Sheet',     '2026-Q2', 'pdf', 'ACTIVE',
   CURRENT_DATE - 30,  'taskflow-price-sheet-2026-Q2.pdf', 3,
   '9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d'),
  ('a0000000-0000-4000-8000-000000000003', 'TaskFlow Brand Guidelines', 'v3',     'pdf', 'ACTIVE',
   CURRENT_DATE - 120, 'taskflow-brand-guidelines-v3.pdf', 18,
   '7f6e5d4c3b2a1908f7e6d5c4b3a29180f7e6d5c4b3a29180f7e6d5c4b3a29180')
ON CONFLICT (document_id) DO NOTHING;

UPDATE guideline_documents
   SET supersedes_id = 'a0000000-0000-4000-8000-000000000001'
 WHERE document_id = 'a0000000-0000-4000-8000-000000000002'
   AND supersedes_id IS NULL;

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------
INSERT INTO rules
  (rule_id, version, type, rule_text, document_id, source_file, source_page, status,
   effective_from, expires_on, supersedes_rule_id, supersedes_version,
   risk_tier, channels, price_sensitive, confirmed_by)
VALUES
  -- the retired price and its replacement -------------------------------------
  ('PRIC-001', 1, 'fact', 'TaskFlow Pro costs $29 per user per month.',
   'a0000000-0000-4000-8000-000000000001', 'taskflow-price-sheet-2026-Q1.pdf', 1, 'SUPERSEDED',
   CURRENT_DATE - 200, CURRENT_DATE + 90, NULL, NULL,
   'high', ARRAY['social','corporate','email','regulated'], TRUE,
   '00000000-0000-4000-8000-000000000001'),

  ('PRIC-002', 1, 'fact', 'TaskFlow Pro costs $34 per user per month.',
   'a0000000-0000-4000-8000-000000000002', 'taskflow-price-sheet-2026-Q2.pdf', 1, 'ACTIVE',
   CURRENT_DATE - 30, CURRENT_DATE + 300, 'PRIC-001', 1,
   'high', ARRAY['social','corporate','email','regulated'], TRUE,
   '00000000-0000-4000-8000-000000000001'),

  -- ACTIVE in the column, expired in reality ----------------------------------
  ('PROMO-001', 1, 'claim', 'Launch offer: 20% off the first year for new workspaces.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 6, 'ACTIVE',
   CURRENT_DATE - 60, CURRENT_DATE - 5, NULL, NULL,
   'high', ARRAY['social','corporate'], FALSE,
   '00000000-0000-4000-8000-000000000003'),

  -- a rule set that contradicts itself -----------------------------------------
  ('TONE-001', 1, 'tone', 'Open every social post with a question.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 4, 'ACTIVE',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'standard', ARRAY['social'], FALSE,
   '00000000-0000-4000-8000-000000000001'),

  ('TONE-002', 1, 'tone', 'Never open a social post with a question; lead with the value.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 7, 'ACTIVE',
   CURRENT_DATE - 100, NULL, NULL, NULL,
   'standard', ARRAY['social'], FALSE,
   '00000000-0000-4000-8000-000000000001'),

  -- terminology ----------------------------------------------------------------
  ('TERM-001', 1, 'term', 'Write the product name as TaskFlow: one word, two capitals.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 2, 'ACTIVE',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'high', ARRAY['social','corporate','email','regulated'], FALSE,
   '00000000-0000-4000-8000-000000000001'),

  ('TERM-002', 1, 'term', 'Call a collection of tasks a workspace, not a project.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 3, 'ACTIVE',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'standard', ARRAY['social','corporate','email'], FALSE,
   '00000000-0000-4000-8000-000000000001'),

  -- claims ---------------------------------------------------------------------
  ('CLAI-001', 1, 'claim', 'Do not claim market leadership without citing an approved source.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 9, 'ACTIVE',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'high', ARRAY['social','corporate','regulated'], FALSE,
   '00000000-0000-4000-8000-000000000003'),

  ('CLAI-002', 1, 'claim', 'Do not promise guaranteed outcomes; state what the product does.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 10, 'ACTIVE',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'high', ARRAY['social','corporate','email','regulated'], FALSE,
   '00000000-0000-4000-8000-000000000003'),

  -- visual / accessibility ------------------------------------------------------
  ('VISU-001', 1, 'visual', 'Use only approved logo files; never recolour the brand mark.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 12, 'ACTIVE',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'high', ARRAY['social','corporate','email'], FALSE,
   '00000000-0000-4000-8000-000000000001'),

  ('VISU-002', 1, 'visual', 'Text over imagery must reach a 4.5:1 contrast ratio.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 14, 'ACTIVE',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'high', ARRAY['social','corporate','email'], FALSE,
   '00000000-0000-4000-8000-000000000001'),

  -- never citable: DRAFT and unconfirmed ---------------------------------------
  ('LEGL-001', 1, 'fact', 'Regulated copy must carry the approved disclaimer block verbatim.',
   'a0000000-0000-4000-8000-000000000003', 'taskflow-brand-guidelines-v3.pdf', 18, 'DRAFT',
   CURRENT_DATE - 120, NULL, NULL, NULL,
   'high', ARRAY['regulated'], FALSE,
   NULL)
ON CONFLICT (rule_id, version) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Content: three items so the app opens onto a populated screen, not an empty
-- state that makes it look unfinished.
-- ---------------------------------------------------------------------------
INSERT INTO content_items (content_id, creator_id, title, channel, publish_date) VALUES
  ('c0000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002',
   'Launch post — TaskFlow Pro', 'social', CURRENT_DATE + 2),
  ('c0000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002',
   'Partner newsletter — April', 'email', CURRENT_DATE + 5),
  ('c0000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001',
   'Homepage hero v2', 'corporate', CURRENT_DATE + 7)
ON CONFLICT (content_id) DO NOTHING;

-- Version 1 of item 1. The hash is left NULL on purpose: the trigger computes it,
-- which proves on every fresh clone that hashing is the database's job.
INSERT INTO content_versions
  (content_version_id, content_id, version_number, content_text, created_by, canonical_hash)
VALUES
  ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 1,
   'Task Flow Pro is now just $29 per user and it is the #1 task app guaranteed to keep your team on track.',
   '00000000-0000-4000-8000-000000000002', NULL),
  ('b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000002', 1,
   'Our fastest growing teams switched to TaskFlow in a single afternoon.',
   '00000000-0000-4000-8000-000000000002', NULL),
  ('b0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000003', 1,
   'TaskFlow keeps every project on track. Start free.',
   '00000000-0000-4000-8000-000000000001', NULL)
ON CONFLICT (content_version_id) DO NOTHING;

-- A check run on item 1, with the three findings the demo opens with ------------
INSERT INTO check_runs (check_run_id, content_version_id, outcome, started_at, completed_at)
VALUES ('d0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001',
        'COMPLETED', now() - INTERVAL '4 minutes', now() - INTERVAL '4 minutes' + INTERVAL '1 second')
ON CONFLICT (check_run_id) DO NOTHING;

-- The five findings the engine produces for this copy, stored verbatim, so what a
-- visitor sees on first load is what a real check returns.
INSERT INTO findings
  (finding_id, check_run_id, status, rule_id, rule_version, evidence_quote,
   span_start, span_end, message, action)
VALUES
  ('e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'CONFIRMED_RULE_MATCH', 'TERM-001', 1, 'Task Flow', 0, 9,
   '“Task Flow” — product name written as two words (TERM-001 v1).',
   'BLOCK_EXPORT'),
  ('e0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000001',
   'SOURCE_CONFLICT_OR_EXPIRED', 'TONE-002', 1,
   'TONE-001 v1 and TONE-002 v1 are both live and give opposite instructions.',
   NULL, NULL,
   'TONE-001 v1 and TONE-002 v1 are both live and give opposite instructions. '
   'We will not guess which one wins.',
   'FLAG_REVIEW'),
  ('e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'CONFIRMED_RULE_MATCH', 'PRIC-002', 1, '$29', 26, 29,
   'Copy states $29. PRIC-002 v1 is live and states $34 per user per month.',
   'BLOCK_EXPORT'),
  ('e0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001',
   'NEEDS_AUTHORISED_REVIEWER', 'CLAI-001', 1, '#1', 53, 55,
   '“#1” — market-leadership claim (CLAI-001 v1).',
   'FLAG_REVIEW'),
  ('e0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000001',
   'NEEDS_AUTHORISED_REVIEWER', 'CLAI-002', 1, 'guaranteed', 65, 75,
   '“guaranteed” — guaranteed outcome (CLAI-002 v1).',
   'FLAG_REVIEW')
ON CONFLICT (finding_id) DO NOTHING;

INSERT INTO finding_rewrites (finding_id, option_label, strategy, rewrite_text) VALUES
  ('e0000000-0000-4000-8000-000000000001', 'A', 'surgical',        '$34'),
  ('e0000000-0000-4000-8000-000000000001', 'B', 'brand_balanced',  'TaskFlow Pro is $34 per user per month'),
  ('e0000000-0000-4000-8000-000000000001', 'C', 'channel_native',  '$34 per user, per month. That is it'),
  ('e0000000-0000-4000-8000-000000000002', 'A', 'surgical',        'TaskFlow'),
  ('e0000000-0000-4000-8000-000000000002', 'B', 'brand_balanced',  'TaskFlow'),
  ('e0000000-0000-4000-8000-000000000002', 'C', 'channel_native',  'TaskFlow'),
  ('e0000000-0000-4000-8000-000000000003', 'A', 'surgical',        'a task app teams rely on'),
  ('e0000000-0000-4000-8000-000000000003', 'B', 'brand_balanced',  'the task app your team will actually keep using'),
  ('e0000000-0000-4000-8000-000000000003', 'C', 'channel_native',  'the task app that sticks'),
  ('e0000000-0000-4000-8000-000000000004', 'A', 'surgical',        'built'),
  ('e0000000-0000-4000-8000-000000000004', 'B', 'brand_balanced',  'built to keep your team on track'),
  ('e0000000-0000-4000-8000-000000000004', 'C', 'channel_native',  'your team, on track'),
  ('e0000000-0000-4000-8000-000000000005', 'A', 'surgical',        'TaskFlow Pro is $34 per user per month. Teams set it up in an afternoon.'),
  ('e0000000-0000-4000-8000-000000000005', 'B', 'brand_balanced',  'TaskFlow Pro is $34 per user per month. Your team picks it up fast and keeps it tidy.'),
  ('e0000000-0000-4000-8000-000000000005', 'C', 'channel_native',  'TaskFlow Pro. $34 per user. Set up before lunch.')
ON CONFLICT (finding_id, option_label) DO NOTHING;

INSERT INTO audit_log (entry_id, content_id, actor_type, actor_id, action, reason, details, occurred_at) VALUES
  ('f0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001',
   'USER', '00000000-0000-4000-8000-000000000002', 'submitted', NULL,
   '{"version_number": 1}'::jsonb, now() - INTERVAL '5 minutes'),
  ('f0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001',
   'SYSTEM', NULL, 'checked', NULL,
   '{"findings": 5, "outcome": "COMPLETED"}'::jsonb, now() - INTERVAL '4 minutes')
ON CONFLICT (entry_id) DO NOTHING;

-- Item 3 is approved, so the ledger and the app have a real approved state to
-- show before anyone touches anything. Neha is a reviewer; Priya is the author,
-- so the database's "no self-approval" rule is satisfied honestly.
INSERT INTO approvals (approval_id, content_id, content_version_id, state, content_hash,
                       approved_by, approved_at)
SELECT 'aa000000-0000-4000-8000-000000000001',
       'c0000000-0000-4000-8000-000000000003',
       'b0000000-0000-4000-8000-000000000003',
       'APPROVED', cv.canonical_hash,
       '00000000-0000-4000-8000-000000000003', now() - INTERVAL '1 day'
  FROM content_versions cv
 WHERE cv.content_version_id = 'b0000000-0000-4000-8000-000000000003'
ON CONFLICT (approval_id) DO NOTHING;

INSERT INTO audit_log (entry_id, content_id, actor_type, actor_id, action, details, occurred_at)
SELECT 'f0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000003',
       'USER', '00000000-0000-4000-8000-000000000003', 'approved',
       jsonb_build_object('version_number', 1, 'content_hash', cv.canonical_hash),
       now() - INTERVAL '1 day'
  FROM content_versions cv
 WHERE cv.content_version_id = 'b0000000-0000-4000-8000-000000000003'
ON CONFLICT (entry_id) DO NOTHING;

COMMIT;
