# Risk Register

Initial risks from the project plan. Review likelihood, impact, and ownership as
implementation and research produce evidence.

| Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- |
| LLM invents a rule or paraphrases evidence | Medium | High | Five verifier gates, strict JSON, grounding golden cases | Verifier/backend |
| Conflicting or expired sources are treated as current | Medium | High | Temporal rules, conflict abstention, admin escalation | Rules/backend |
| Hash differs because canonicalization is inconsistent | Medium | High | One canonicalization contract and five edit-void tests | Approval/backend |
| PDF rule extraction is unreliable | Medium | Medium | Keep proposals in DRAFT until admin confirmation | Ingestion/backend |
| API key leak or cost overrun | Low | High | Environment-only secrets, rate limits, spend cap | API owner |
| Research targets are missed | High | Medium | Start interviews early; report measured counts honestly | Research lead |
| Scope expands beyond F1-F8 and F11 | High | High | Freeze MVP; defer F9/F10 and out-of-scope integrations | Team lead |
| Demo fails live | Medium | High | Seeded fictional TaskFlow data and recorded fallback | Demo owner |
| Team burnout | Medium | Medium | Plan breaks and share review load | Team |

Owners are roles, not assigned individuals. Confirm named owners with the team.
