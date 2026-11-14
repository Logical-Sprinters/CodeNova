# 07 · Decisions

Eight decisions that shaped this build, each with the alternative that was rejected. The
point of writing them down is that a reviewer can disagree with a decision instead of
guessing at one.

---

### D1 · Invariants live in the database, not in the service layer
**Decision.** The four guarantees (hash is computed, a new version voids the approval, a
confirmed finding cites a live rule, only an active non-author reviewer approves) are
`TRIGGER`s and `CHECK`s.
**Why.** A rule in a service method holds only for the code paths that remember to call it.
A trigger holds for every path, including a `psql` session at 2am.
**Rejected.** Service-layer enforcement with tests. Cheaper to write, impossible to promise.

### D2 · One Flutter app for phone and laptop, not a mobile app plus a web app
**Decision.** A single Dart codebase. `MediaQuery` switches bottom navigation to a
`NavigationRail` at 720 px.
**Why.** Two clients is two redesigns, two build pipelines and two demo paths for one
person's weekend. One codebase also means the fallback demo target (Chrome) costs nothing —
the code does not change, only the target.
**Rejected.** Flutter app + Next.js web console.

### D3 · No ORM; explicit SQL with psycopg
**Decision.** Queries are written by hand, rows come back as dicts.
**Why.** The SQL is the artefact being defended. An ORM would add a second model of the same
data that can disagree with the first, and the disagreement would be discovered at the worst
moment.
**Rejected.** SQLAlchemy. It would have saved an hour and cost the ability to defend the
schema by pointing at it.

### D4 · The checker is deterministic; no model in the request path
**Decision.** Regex and price comparison over live rules. No network call, no key.
**Why.** Three reasons in order of weight: it cannot invent a rule; it works with no network,
no rate limit and no cost; and a finding can be defended in one sentence ("this rule, this
version, this span"). A model adds coverage and subtracts all three.
**Rejected.** LLM-based checking. It stays on the roadmap **behind the same citation
contract**, as advisory output that can never become the blocking layer.

### D5 · Three repairs per finding, as templates
**Decision.** Every finding offers `A surgical`, `B brand_balanced`, `C channel_native`,
generated from templates, not from a model.
**Why.** "Fix it" is not advice. Three named strategies turn a complaint into a choice, and
templates cannot fail during a demo.
**Cost.** The copy is only as good as the template. That is visible, and honest, and the
repairs are labelled as templates rather than as writing.

### D6 · The audit log is append-only, but approvals are not
**Decision.** `audit_log` refuses `UPDATE`/`DELETE`. `approvals` rows *are* updated — from
`APPROVED` to `VOID` — and the update is recorded in the log.
**Why.** Saying "approvals are append-only" would be false, and the truthful version is
stronger: an approval is bound to an immutable version by hash, and the binding is what
breaks, loudly and traceably.
**Rejected.** Modelling voids as new rows and calling the whole thing append-only. It reads
better and describes the system less accurately.

### D7 · Identity is a header, and says so
**Decision.** `X-User-Id`, looked up in `users`, role read from the row. No password, no
token.
**Why.** A half-built JWT stack is worse than an honest header: it invites the assumption
that authentication exists. The role checks that matter are real and are enforced twice.
**Rejected.** Fake login screens with a hard-coded password — which is the usual way this
goes and the easiest way to lose a viva.

### D8 · Delete the design's invented numbers and badges
**Decision.** The generated UI contained fabricated figures (1,428 events, 98.4% verified,
"node #849,102", "batch #892-D") and compliance badges (SOC 2, Okta SAML, Cloudflare TLS).
All removed.
**Why.** Those are checkable claims. A single "where does 98.4% come from?" ends the
credibility of everything else on the screen. Every number now comes from an API field, or
the screen shows a dash.
**Rejected.** Keeping them because they look impressive. They do — for about four seconds.

---

## Smaller decisions worth knowing

| Decision | Reason |
|---|---|
| Seed dates are relative to `CURRENT_DATE` | a demo that only works in the month it was written is not a demo |
| `flutter create` scaffolding (`android/`, `web/`) is committed | a clone runs without an extra step; `lib/` is never generated |
| Manrope is bundled, not fetched at runtime | a font fetch is a blank-looking demo on conference wifi |
| One dependency in the app (`http`) | every package is a build that can fail on a machine this project does not control |
| Hand-written models | eight `fromJson` methods cost less than a codegen stage that can fail |
| Tests run inside a rolled-back transaction | the assertion suite is safe against a live demo database |
