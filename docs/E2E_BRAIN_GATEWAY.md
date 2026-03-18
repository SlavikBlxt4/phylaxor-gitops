# Brain Gateway E2E Validation

This document describes the repeatable end-to-end validation for the current core Phylaxor flow:

`alert -> ingest -> enricher -> decision -> brain-gateway -> notifier -> Telegram`

## Current Status

This flow has already been validated successfully in OpenShift.

What this means:
- `ingest` accepts and normalizes the alert
- `enricher` enriches and forwards it
- `decision` calls Brain Gateway
- Brain Gateway returns a valid AI response
- `decision` persists the result as `path=ai`
- `notifier` sends the resulting recommendation

## Important Namespace Detail

Application services run in:
- `phylaxor`

Database services run in:
- `phylaxor-db`

That matters for verification, because the Postgres pod used to inspect `decisions` and `ai_usage` lives in `phylaxor-db`.

## Recommended Validation Command

Run:

```bash
cd phylaxor-gitops
./e2e_brain_gateway.sh
```

## What The Script Verifies

The script:
- deploys or upgrades the application chart
- triggers a unique alert against `ingest`
- waits for a `decisions` row for that alert
- verifies that the persisted path is `ai`
- verifies that `ai_request_id` is present
- verifies that `ai_usage` contains a row for that request
- verifies logs across `ingest`, `enricher`, `decision`, `brain-gateway`, and `notifier`

## Success Criteria

The run is successful only if:
- a decision row exists for the injected alert
- `decisions.path = ai`
- an `ai_usage` row exists for the same request
- `decision` logs `brain_response`
- `decision` logs `decision_made path=ai`
- `decision` logs `notifier_sent`
- `brain-gateway` logs the request id

If Telegram credentials are active, notifier should log a real send.
If notifier is in dry-run mode, the script reports that separately.

## Related Files

- `../e2e_brain_gateway.sh`
- `../../phylaxor-project/docs/PROJECT_CONTEXT.md`
- `../../phylaxor-project/docs/TEST_MATRIX.md`
