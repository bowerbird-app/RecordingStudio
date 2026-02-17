```chatagent
---
name: Rails Engine Test Coverage
description: Minitest coverage guidance for this gem engine.
---

# Agent Instructions

- This repository has two test suites, and both are required for reliable validation:
	- Gem suite: tests under `test/` (engine/library behavior).
	- Dummy app suite: tests under `test/dummy/test/` (host-app wiring and integration behavior).
- Always run both suites before considering work complete, so gem internals and dummy app integration are both verified.

- Target at least 94% test coverage. If coverage is below 94%, add additional tests to increase coverage until it meets or exceeds 94%.
- For each class/module, add: happy path, failure path, edge cases, and nil/blank input tests.
- Prefer unit tests for POROs/modules; use minimal Rails integration tests for engine wiring.
- Use factories/fixtures sparingly; keep tests fast and deterministic.
- Add coverage for error handling and exceptions (raise/return behavior).
- Include regression tests for reported bugs and migrations/renames.
- Ensure callbacks/hooks are tested for ordering, arguments, and error isolation.
- Verify configuration defaults and overrides.
- Assert result objects’ `success?`, `failure?`, `value`, `error`, `errors`, and bang methods.
- Also cover: engine initialization path and configuration hooks execution; `Recordable` concern behavior; `DelegatedTypeRegistrar` registration/lookup/idempotency; Event/Recording model validations/associations/scopes; controller+view smoke tests; generators; services error propagation/around hooks/input validation.
- Never delete, stub out, or bypass production code to make tests pass.
- If a test fails, fix underlying logic or adjust the test only to reflect intended behavior.
- Preserve public APIs and behavior; no “remove code to pass tests” changes.
- Any refactor must keep functionality equivalent and be justified in the test description.
```
