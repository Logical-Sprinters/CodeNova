# Documentation Status and Reading Order

This repository includes both current implementation notes and the original product-design documents.

## Read in this order after cloning

1. [Root README](../README.md) — install/run overview.
2. [Implementation Status](IMPLEMENTATION_STATUS.md) — accurate implemented/partial/not implemented inventory.
3. [AI Handoff](AI_HANDOFF.md) — code paths, API flow, constraints and continuation tasks.
4. [Architecture](architecture.md) and [Application Flow](app-flow.md) — current vertical slice versus target product.
5. [PRD](prd.md), [TRD](trd.md), [Frontend Specification](frontend-specification.md), [Backend Schema](backend-schema.md), and [Data Contracts](data-contracts.md) — intended product/system design, not a claim that all features exist.

## Documentation interpretation

The PRD/TRD and several security, schema, research, and golden-test documents were written as proposal/design baselines. Their acceptance criteria, diagrams, roles, PostgreSQL model and planned AI verifier describe the desired broader product. Use `IMPLEMENTATION_STATUS.md` to determine whether a feature is actually in code.

The current prototype's core reality: FastAPI + deterministic regex rules + JSON file persistence + Flutter Web API integration. AI abstains without verified facts. There is no production database, auth, or production audit log.
