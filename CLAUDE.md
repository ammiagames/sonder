# CLAUDE.md — Engineering Quality & Regression Prevention

This repository values **stability, correctness, and maintainability**.  
When developing new features or making changes, your #1 goal is: **do not introduce regressions**.

## Core Principles

### 1) No regressions by default
- Any change must preserve existing behavior unless the change explicitly intends to modify it.
- Treat every bugfix, refactor, and feature as a potential regression risk.
- Prefer small, reviewable diffs over large, sweeping rewrites.

### 2) Research thoroughly before changing code
Before implementing:
- Identify the exact files, functions, and data flows involved.
- Search for existing patterns and conventions used in similar parts of the codebase.
- Confirm assumptions by reading the actual implementation (not just interfaces/types).
- If behavior is ambiguous, locate existing tests, docs, or usage examples to infer intent.

Deliverable expectation:
- Summarize findings (what you looked at, what you learned, what you will change).
- Call out risks and edge cases you discovered.

### 3) Changes should be measurable and verifiable
Every meaningful change should have at least one of:
- A test (unit/integration/e2e)
- A reproducible verification step (manual or scripted)
- Logging/telemetry changes that prove correctness (where appropriate)

If you cannot add tests (e.g., legacy constraints), document:
- why not
- what you did instead (manual verification steps, targeted logging, etc.)

---

## Workflow Requirements

### Step A — Understand current behavior
- Reproduce the current behavior (or read tests that define it).
- Identify "must not break" behaviors and list them.
- Note boundary conditions: empty inputs, large inputs, error states, partial failures.

### Step B — Plan the change
Provide a short plan that includes:
- Scope of files/modules to touch
- A rollback strategy (how to revert safely if needed)
- A testing plan (what tests will be added/updated and what manual checks will be done)

### Step C — Implement conservatively
- Prefer extending existing abstractions over inventing new ones.
- Avoid unrelated refactors bundled into feature work.
- Keep changes isolated and reversible.
- Maintain backward compatibility unless explicitly directed otherwise.

### Step D — Test like you’re trying to break it
Minimum expectations:
- Run the relevant automated test suite(s).
- Add tests that cover:
  - the “happy path”
  - edge cases
  - previously-broken scenarios (for bugfixes)
  - concurrency/ordering issues when relevant
- Verify negative cases: invalid inputs, failures, timeouts, missing dependencies.

For high-risk changes:
- Add integration tests (not only unit tests).
- Add a targeted regression test that fails before the change and passes after.

### Step E — Validate before concluding
Before marking work “done”:
- Confirm existing tests still pass.
- Confirm newly added tests pass.
- Confirm linting/type checks/build steps pass (if present).
- Provide explicit verification notes:
  - commands run
  - results
  - manual steps performed

---

## “Big Piece of Code” Rule (High Impact Changes)

A “big piece” includes: new modules, major refactors, new infrastructure, new API endpoints, new data models, new persistence, auth/security changes, or anything that could affect many flows.

For these changes:
1. **Design first** (brief but clear)
   - What problem it solves
   - Proposed approach
   - Alternatives considered
   - Risks + mitigations
2. **Incremental delivery**
   - Land changes in small steps where possible.
   - Use feature flags/config toggles when applicable.
3. **Extra testing**
   - Add integration/e2e coverage if the change affects user-facing behavior.
   - Add performance checks if the change affects hot paths.
4. **Backwards compatibility**
   - Migrations must be safe, reversible, and ideally two-phase.
   - Avoid breaking API contracts without versioning.

---

## Regression Checklist (Use Before Finalizing)

- [ ] I identified and preserved existing behavior (or documented intentional changes).
- [ ] I searched for similar patterns in the codebase and followed them.
- [ ] I considered edge cases and failure modes.
- [ ] I added or updated tests to cover the change.
- [ ] I ran the relevant test suites and checks.
- [ ] I verified the change manually if needed and documented steps.
- [ ] The diff is scoped (no unrelated refactors).
- [ ] Risky changes have mitigations (feature flag, rollback plan, migration safety).

---

## Communication Style in PRs / Summaries

When describing work, include:
- What changed and why
- What did NOT change (guarantees / preserved behavior)
- How it was tested (commands + key cases)
- Known risks or follow-ups (if any)

---

## If Something Is Unclear

Stop and investigate before coding:
- Look for tests defining behavior.
- Look for docs/comments/usage sites.
- If still unclear, propose a conservative default and document the assumption.
- Never guess silently.

---

## Definition of Done

A change is “done” when:
- It introduces no unintended regressions
- It is covered by tests or clear verification steps
- It matches repository conventions
- It is understandable and maintainable by someone else
