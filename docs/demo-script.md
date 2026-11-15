# Current Prototype Demo Script

Use fictional copy and sample Acme rules. This walkthrough demonstrates the current vertical slice—not the full proposed TaskFlow product.

## 3–5 minute walkthrough

1. Start FastAPI; show `http://127.0.0.1:8000/docs` and `/health`.
2. Run BrandGuard Flutter Web in Chrome.
3. Open New Brand Check and enter draft text containing sample strings such as `guaranteed`, `100% safe`, `free forever`, and `best in the world`.
4. Run the check; show Flutter calling FastAPI and receiving check ID, receipt ID and deterministic findings.
5. In Findings & Evidence, point out rule ID, severity, matched phrase and message. Explain these are regex checks against fictional sample rules.
6. Open Review Queue; explain records are fetched from `GET /api/v1/reviews`.
7. Approve or reject a pending record; inspect the stored decision via Swagger. Request Changes maps to rejected with a reason note.
8. Use approval verification in Swagger with the exact approved content, then modify one character and demonstrate hash mismatch. The Flutter verification UI may still need wiring.
9. Show the receipt API response; Flutter receipt presentation remains in progress.

## Be transparent about limitations

- AI verifier abstains because trusted facts/provider are not connected.
- JSON files provide local persistence; PostgreSQL is not the runtime database.
- Authentication, role enforcement, immutable version lifecycle, full audit log, guideline ingestion and production security are not implemented.
- Acme rules are fictional and not official rules of any real brand.

Keep a backup recording. Do not present planned features as delivered.
