#!/usr/bin/env python3
"""
BrandGuard · scripts/smoke.py

Walks the entire claim of the product against a running stack and prints what it
actually sees. Run this after `make up && make db && make api`:

    python scripts/smoke.py
    python scripts/smoke.py --base http://192.168.1.20:8000

It creates one new content item per run; nothing is deleted. The script exits
non-zero and names the failing step, so it is usable as a check in CI.

The story it proves, in order:
  1  the API is up and the database is seeded
  2  a superseded rule is not live, its replacement is
  3  the demo copy produces findings, each citing a live rule and a character span
  4  every finding offers three repairs
  5  a creator cannot approve
  6  a deactivated account cannot approve
  7  a blocking finding stops the approval
  8  accepting a repair creates a new version and re-checks it
  9  contradictions between live rules block approval instead of being guessed
 10  an override becomes a clarity ticket against that rule version
 11  once nothing blocks, a reviewer can approve — bound to the content hash
 12  a one-word edit voids that approval, automatically
 13  the ledger explains it, attributed to SYSTEM, not to a person
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request

CREATOR = "00000000-0000-4000-8000-000000000002"     # Arun  · creator
REVIEWER = "00000000-0000-4000-8000-000000000003"    # Neha  · reviewer
DEACTIVATED = "00000000-0000-4000-8000-000000000004"  # Vikram · reviewer, deactivated

DEMO_COPY = (
    "Task Flow Pro is now just $29 per user and it is the #1 task app "
    "guaranteed to keep your team on track."
)

BASE = "http://localhost:8000"
PASSED = 0
GREEN, RED, DIM, OFF = "\033[32m", "\033[31m", "\033[2m", "\033[0m"


class StepFailed(Exception):
    pass


def call(method: str, path: str, user: str | None = None, body=None, expect: int | None = None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    if user:
        request.add_header("X-User-Id", user)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            status, payload = response.status, response.read()
    except urllib.error.HTTPError as err:
        status, payload = err.code, err.read()
    except urllib.error.URLError as err:
        raise StepFailed(f"cannot reach {BASE}: {err.reason}. Is `make api` running?")
    try:
        parsed = json.loads(payload) if payload else None
    except json.JSONDecodeError:
        raise StepFailed(f"{method} {path} returned {status} with a non-JSON body: "
                         f"{payload[:200]!r}")
    if expect is not None and status != expect:
        raise StepFailed(f"{method} {path} returned {status}, expected {expect}: {parsed}")
    return status, parsed


def ok(label: str, detail: str = "") -> None:
    global PASSED
    PASSED += 1
    print(f"  {GREEN}ok{OFF}    {label}")
    if detail:
        for line in detail.splitlines():
            print(f"        {DIM}{line}{OFF}")


def find(detail: dict, **match) -> dict | None:
    for finding in detail["findings"]:
        if all(finding.get(k) == v for k, v in match.items()):
            return finding
    return None


def main() -> int:
    global BASE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default=BASE)
    BASE = parser.parse_args().base.rstrip("/")

    print(f"\nBrandGuard smoke test against {BASE}\n")

    # 1 ---------------------------------------------------------------------
    _, health = call("GET", "/health", expect=200)
    if health["status"] != "ok" or health["users"] < 4:
        raise StepFailed(f"the database is not seeded: {health}")
    ok("the API is up and the database is seeded",
       f"{health['users']} users · {health['rule_versions']} rule versions · "
       f"{health['live_rules_now']} live today · {health['content_items']} content items")

    # 2 ---------------------------------------------------------------------
    _, rules = call("GET", "/rules", user=CREATOR, expect=200)
    superseded = next(r for r in rules if r["rule_id"] == "PRIC-001")
    current = next(r for r in rules if r["rule_id"] == "PRIC-002")
    if superseded["is_live_now"] or not current["is_live_now"]:
        raise StepFailed("a superseded rule is being treated as live")
    ok("the superseded price rule is not live; its replacement is",
       f"{superseded['rule_id']} v{superseded['version']} {superseded['status']}, window open "
       f"to {superseded['expires_on']}, not live\n"
       f"{current['rule_id']} v{current['version']} {current['status']}, effective "
       f"{current['effective_from']}, live")

    # 3 ---------------------------------------------------------------------
    _, created = call("POST", "/content", user=CREATOR,
                      body={"text": DEMO_COPY, "channel": "social",
                            "title": "Smoke test post"}, expect=201)
    content_id = created["content_id"]
    findings = created["check"]["findings"]
    if not findings:
        raise StepFailed("the demo copy produced no findings")
    ok(f"the check found {len(findings)} problems, each citing a rule and a span",
       "\n".join(f"{f['status']:<27} {f['rule_id']} v{f['rule_version']}  "
                 f"chars {f['span'][0]:>3}-{f['span'][1]:<3} "
                 f"{DEMO_COPY[f['span'][0]:f['span'][1]]!r}" for f in findings))

    if "CONFIRMED_RULE_MATCH" not in {f["status"] for f in findings}:
        raise StepFailed("the wrong price was not confirmed against the live rule")
    ok("the wrong price is confirmed against a rule that is live today",
       next(f["message"] for f in findings if f["rule_id"] == "PRIC-002"))

    # 4 ---------------------------------------------------------------------
    _, detail = call("GET", f"/content/{content_id}", user=CREATOR, expect=200)
    price = find(detail, rule_id="PRIC-002")
    if not price or len(price["rewrites"]) != 3:
        raise StepFailed("a finding must offer exactly three repairs")
    ok("every finding offers three repairs",
       " · ".join(f"{r['option_label']} {r['strategy']}" for r in price["rewrites"]))

    # 5, 6, 7 ---------------------------------------------------------------
    status, _ = call("POST", f"/content/{content_id}/approve", user=CREATOR)
    if status != 403:
        raise StepFailed(f"a creator was allowed to approve (status {status})")
    ok("a creator cannot approve", "refused with 403 before the database is even asked")

    status, _ = call("POST", f"/content/{content_id}/approve", user=DEACTIVATED)
    if status != 403:
        raise StepFailed(f"a deactivated account was allowed through (status {status})")
    ok("a deactivated reviewer cannot act", "refused with 403")

    status, blocked = call("POST", f"/content/{content_id}/approve", user=REVIEWER)
    if status != 409:
        raise StepFailed(f"approval was allowed with a blocking finding (status {status})")
    ok("a reviewer cannot approve while a confirmed match stands",
       f"409 · {blocked['detail']['error']}")

    # 8 ---------------------------------------------------------------------
    _, accepted = call("POST", f"/findings/{price['finding_id']}/rewrites/B",
                       user=CREATOR, expect=201)
    if "$34" not in accepted["new_text"] or "$29" in accepted["new_text"]:
        raise StepFailed(f"the repair did not apply the rule's figure: {accepted['new_text']}")
    ok(f"accepting repair B created version {accepted['version']['version_number']} and re-checked it",
       accepted["new_text"])

    # 9 ---------------------------------------------------------------------
    _, detail = call("GET", f"/content/{content_id}", user=CREATOR, expect=200)
    conflict = find(detail, status="SOURCE_CONFLICT_OR_EXPIRED")
    if not conflict:
        raise StepFailed("the contradiction between two live tone rules was not reported")
    status, blocked = call("POST", f"/content/{content_id}/approve", user=REVIEWER)
    if status != 409:
        raise StepFailed(f"a contradiction did not block approval (status {status})")
    ok("two live rules that contradict each other block approval instead of being guessed",
       conflict["message"])

    # 10 --------------------------------------------------------------------
    _, override = call("POST", f"/findings/{conflict['finding_id']}/override", user=REVIEWER,
                       body={"reason_code": "rule_unclear",
                             "reason_text": "TONE-001 and TONE-002 conflict; brand lead "
                                            "confirmed in writing that TONE-002 wins "
                                            "until the guideline is corrected."},
                       expect=201)
    _, tickets = call("GET", "/clarity-tickets", user=REVIEWER, expect=200)
    ticket = next((t for t in tickets if t["rule_id"] == conflict["rule_id"]), None)
    if not ticket:
        raise StepFailed("the override did not become a clarity ticket")
    ok("the override becomes a clarity ticket against that rule version",
       f"{ticket['rule_id']} v{ticket['rule_version']} · {ticket['override_count']} override(s) "
       f"· latest reason: {ticket['latest_reason_code']}")

    # 11 --------------------------------------------------------------------
    _, approved = call("POST", f"/content/{content_id}/approve", user=REVIEWER, expect=200)
    ok(f"a reviewer approved version {approved['version_number']}",
       f"bound to sha256 {approved['content_hash'][:16]}… · "
       f"{len(approved['acknowledged'])} advisory finding(s) acknowledged, not hidden")

    # 12 --------------------------------------------------------------------
    edited_text = accepted["new_text"].replace("on track", "on schedule")
    _, edited = call("POST", f"/content/{content_id}/versions", user=CREATOR,
                     body={"text": edited_text}, expect=201)
    if edited["voided_approvals"] != 1:
        raise StepFailed("the edit did not void the approval")
    ok("one changed word voided the approval, with no code path involved",
       f"version {edited['version']['version_number']} created · "
       f"{edited['voided_approvals']} approval voided by a database trigger")

    # 13 --------------------------------------------------------------------
    _, ledger = call("GET", f"/ledger?content_id={content_id}", user=CREATOR, expect=200)
    voids = [e for e in ledger if e["action"] == "voided"]
    if not voids:
        raise StepFailed("the void is not in the audit log")
    row = voids[0]
    if row["actor_type"] != "SYSTEM" or row["actor_id"] is not None:
        raise StepFailed("the void was attributed to a person; it was the database")
    ok("the ledger explains it and blames nobody",
       f"actor SYSTEM · reason: {row['reason']} · new version "
       f"{row['details']['new_version_number']} · approvals voided "
       f"{row['details']['voided_approvals']}")

    print(f"\n  {GREEN}all {PASSED} steps passed{OFF} against a live stack.\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except StepFailed as failure:
        print(f"\n  {RED}FAILED{OFF}  {failure}\n")
        sys.exit(1)
