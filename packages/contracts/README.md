# Shared Contracts

These JSON Schemas are the source contracts for API and web types. Generate
Pydantic v2 models and TypeScript types from them when code generation is added;
do not maintain divergent hand-written request shapes.

Contract changes should be reviewed with the API, frontend, and golden tests.
The schemas describe data shape only; active-rule verification, access control,
and state-transition rules still require server-side enforcement.
