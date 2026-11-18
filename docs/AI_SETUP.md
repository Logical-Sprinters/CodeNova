# BrandGuard AI — configured OpenRouter path, wallet funding pending

## Current hosted state

- Provider path: Antideploy's OpenRouter integration, one existing application key.
- Base URL: `https://openrouter.ai/api/v1`.
- Selected model: `openai/gpt-5.4-mini`. Its public catalog entry advertises structured
  outputs; catalog presence is not a funded request or measured quality proof.
- **Wallet ₹0; deployed `AI_PROVIDER=disabled`. No live paid inference was run.**
- Rules, human review, drafts, files and receipts work without AI. Disabled AI returns
  explicit abstention, never a fictional factual pass.

Owner funding: https://antideploy.com/settings/billing#add-money .
**15% fee: ₹100 wallet credit costs ₹115.** Agents cannot add money and no payment
was made. Do not create another AI key or ask the user to paste one into chat.

## After the owner funds the wallet

On the SAME application's server-only variables:

```dotenv
AI_PROVIDER=openrouter
AI_BASE_URL=https://openrouter.ai/api/v1
AI_MODEL=openai/gpt-5.4-mini
```

`OPENROUTER_API_KEY` is already injected by the platform. Do not copy it into source,
Flutter, command-line arguments, screenshots, documentation or a duplicate host
variable. Redeploy the existing app after changing environment so the process uses
it. Verify wallet/provider access, cost limits and real quality before claiming done.
The existing direct-OpenAI adapter remains compatible for a separately authorized
configuration, but it is not the selected hosting path and requires no new choice now.

## Grounded-output contract

1. A reviewer adds/manual-enters or uploads source text, then explicitly verifies it.
2. API selects enabled verified facts for the submitted brand. It splits text into
   overlapping 3,000-character passages (2,700-character stride), ranks lexical overlap
   and retrieves at most five passages. This is not embeddings/vector retrieval.
3. Relevant verified evidence, opted-in provider and a key are all required. The
   exact submission is limited to 12,000 characters for AI comparison.
4. Provider uses strict JSON schema, `store:false`, a 3,000 completion-token cap and
   25-second timeout. OpenRouter routing requires supported parameters and requests
   `data_collection:deny`; GPT-5-family routing uses low/excluded reasoning output.
5. Independently of model schema compliance, server verifies passage IDs, verbatim
   source quotations, content spans, source hashes, result/status consistency and
   completion/refusal state. Invalid/unsupported output abstains.
6. Human review still decides publication. A quote/hash proves provenance of the
   compared text, not its truth, recency, completeness or semantic contradiction.

No evidence, disabled/missing access, provider credit denial/failure/timeout/refusal,
malformed output or fabricated citations → **abstained**. Deterministic checks still run.
There is no claim of automatic publication approval or universally complete fact coverage.

## Live acceptance still required

After funding/activation, test a known matching statement, a contradiction and an
unrelated/unsupported claim against reviewer-verified sources. Inspect actual quotes,
findings, costs, empty-evidence behavior and provider-failure fallback. Mocked contract
tests, model catalog metadata and a provisioned key do not replace this live test.

Enabling AI sends the submitted text and retrieved passages to an external provider.
Request privacy flags are not legal zero-retention/data-residency guarantees. Check
provider terms and organizational permissions before confidential/customer content.
No crawler, independent source verification, OCR, spend UI or inference queue is added.

See [DEPLOYMENT.md](../DEPLOYMENT.md) and the current `validation/RESULTS.md` for the
separate already-completed hosting, email and non-AI workflow checks.
