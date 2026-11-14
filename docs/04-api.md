# 04 · API

Base URL `http://localhost:8000`. Interactive docs at `/docs` (FastAPI generates them from
the same code, so they cannot drift from this page — this page explains the *why*, the
docs list the fields).

Sixteen endpoints, seven routers, no ORM.

## Identity

Every endpoint except `/health` requires:

```
X-User-Id: 00000000-0000-4000-8000-000000000002
```

That is the whole of authentication here, and it is the first item in
[06-limitations.md](06-limitations.md). What it does buy: the server reads the role from
`users` on every request and the database re-checks it inside the approval trigger, so a
client cannot grant itself a permission by asking nicely.

Seeded identities:

| User id | Name | Role | Note |
|---|---|---|---|
| `…0001` | Priya Raman | admin | author of the approved homepage hero |
| `…0002` | Arun Mehta | creator | agency copywriter — the one who writes |
| `…0003` | Neha Kulkarni | reviewer | can approve |
| `…0004` | Vikram Shah | reviewer | **deactivated** — must be refused |

## System

### `GET /health`
No identity required. Returns row counts, so a green response proves the database is
reachable **and** populated.

```json
{"status":"ok","database":"reachable","users":4,"rule_versions":12,
 "live_rules_now":9,"content_items":3,"findings":5,"audit_entries":3,
 "server_date":"2026-11-14"}
```

### `GET /users`
The sign-in list: id, display name, email, role. Active users only.

## Guidelines

### `GET /rules?channel=social`
Every rule version with `is_live_now` computed by `v_live_rules`. Includes superseded and
draft versions on purpose — the guidelines screen exists to show that history.

```json
{"rule_id":"PRIC-001","version":1,"type":"fact",
 "rule_text":"TaskFlow Pro costs $29 per user per month.",
 "source_file":"taskflow-price-sheet-2026-Q1.pdf","source_page":1,
 "status":"SUPERSEDED","effective_from":"2026-04-28","expires_on":"2027-02-12",
 "risk_tier":"high","channels":["social","corporate","email","regulated"],
 "price_sensitive":true,"is_live_now":false}
```

### `GET /documents`
Source documents with a rule count and a checksum.

## Content

### `GET /content`
Every item, newest first, joined to its latest version and approval state, with
`blocking_findings` and `total_findings` computed in SQL.

### `POST /content` → 201
```json
{"text": "Task Flow Pro is now just $29 per user …", "channel": "social", "title": "Launch post"}
```
Creates the item, version 1 (hash computed by the database), an audit `submitted` row, and
runs the check immediately.

Response:
```json
{"content_id":"…","version":{"version_number":1,"canonical_hash":"9a54e4…"},
 "check":{"outcome":"COMPLETED","finding_count":5,"live_rules_considered":9,
          "findings":[{"status":"CONFIRMED_RULE_MATCH","rule_id":"PRIC-002",
                       "span":[26,29],"message":"Copy states $29. …"}]}}
```

### `GET /content/{id}`
One round trip for the findings screen: item, latest version, latest check run, all
findings with their rule text and their three repairs, and the latest approval including
`voided_at` / `void_reason` / `void_diff`.

### `POST /content/{id}/versions` → 201
`{"text": "…"}` — creates version *n+1*, re-checks it, and reports how many approvals were
voided:
```json
{"version":{"version_number":3,…},"check":{…},"voided_approvals":1}
```
`voided_approvals` is a report, not an action: the trigger did it.

### `POST /content/{id}/checks`
Re-run the check on the current version without editing anything.

### `POST /content/{id}/approve`
Reviewer or admin only. Refuses when the version's author is the approver, when the account
is deactivated, or when the hash does not match.

| Situation | Status |
|---|---|
| unresolved `CONFIRMED_RULE_MATCH` / `SOURCE_CONFLICT_OR_EXPIRED` | **409** + the findings |
| caller is a creator | **403** |
| already approved | **409** |
| success | **200**, with the version number, the hash, and the advisory findings that were acknowledged |

Advisory (`UNSUPPORTED`, `AI_INTERPRETATION`, `NEEDS_AUTHORISED_REVIEWER`) findings are
returned as `acknowledged`, and the list is written into the audit row. They inform the
reviewer; they never silently disappear.

## Findings

### `GET /findings/{id}/rewrites`
The three repairs:
```json
[{"option_label":"A","strategy":"surgical","rewrite_text":"$34","accepted":false},
 {"option_label":"B","strategy":"brand_balanced","rewrite_text":"TaskFlow Pro is $34 per user per month.","accepted":false},
 {"option_label":"C","strategy":"channel_native","rewrite_text":"TaskFlow Pro. $34 per user, per month.","accepted":false}]
```

### `POST /findings/{id}/rewrites/{A|B|C}` → 201
Applies the repair and **creates a new content version** — accepting a suggestion is an
edit, not a magic fix, so it voids any standing approval exactly like typing would.
A `surgical` repair replaces the matched phrase; `brand_balanced` and `channel_native`
replace the sentence that contains it, because a figure dropped into the middle of a
sentence leaves a second, worse sentence behind.

### `POST /findings/{id}/override` → 201
```json
{"reason_text": "Brand lead confirmed TONE-002 wins until the guideline is fixed.",
 "reason_code": "rule_unclear"}
```
`reason_text` is required (≥ 3 characters, enforced in the schema) and is written to both
`overrides` and the audit row. One override per finding. The result shows up in
`GET /clarity-tickets`.

## Review and audit

### `GET /queue`
What a reviewer can act on now: not approved, and **nothing blocking unresolved**. Items
with a confirmed match are deliberately absent — they have to be repaired first.

### `GET /ledger?content_id=…`
Newest first, limit 200. `actor_type` is `USER` when a person acted and `SYSTEM` when the
database did, with `actor_id` null in that case.

### `GET /clarity-tickets`
Overrides grouped by rule version: `override_count`, `distinct_people`, `last_raised_at`,
`latest_reason`. This is the third product differentiator as a query — a rule that keeps
being overruled is a rule that is wrong.

## Errors

Every failure carries a sentence a person can act on, not a code.

| Status | Shape | When |
|---|---|---|
| 401 | `{"detail":"X-User-Id header is required"}` | no identity |
| 403 | `{"detail":"approval requires a reviewer"}` | wrong role, deactivated account |
| 404 | `{"detail":"content not found"}` | unknown id |
| 409 | `{"detail":{"error":"blocking findings must be resolved first","findings":[…]}}` | approval refused by the service |
| 422 | `{"detail":"…"}` | a constraint in the database refused the write, in its own words |
| 500 | — | should not happen; `SafeJSONResponse` exists so a `UUID` in an error body cannot become one |

`422` is deliberate: when the database refuses, the API reports the database's words
(`the author of a version cannot approve it`) rather than inventing a friendlier, vaguer one.
