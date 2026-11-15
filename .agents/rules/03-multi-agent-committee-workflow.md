# Rule: Multi-Agent Committee Workflow & Sign-Off Gate

## Scope & Applicability
Applies to complex architectural tasks, refactoring, storage migrations, security implementations, networking protocol changes, and critical business logic.

## The 3-Role Committee Workflow

```
+--------------------------+       +--------------------------+       +--------------------------+
| 1. Test Architect (TDD)  | ----> | 2. Core Developer (Impl) | ----> | 3. QA Adversary/Gatekeep |
+--------------------------+       +--------------------------+       +--------------------------+
```

### Phase 1: Test Architect (TDD Specialist)
- **Role**: Analyzes specifications and creates comprehensive automated test suites and test fixtures before any production code is written.
- **Goal**: Tests rigorously exercise requirements, boundary conditions, and failure states. Tests fail as expected initially (Red phase).

### Phase 2: Core Developer (Implementation Specialist)
- **Role**: Develops the minimal, high-quality production code required to turn all Phase 1 tests green.
- **Goal**: Clean, well-documented, modular implementation adhering to design contracts and architecture rules (Green phase).

### Phase 3: QA Adversary & Gatekeeper (Sign-Off Auditor)
- **Role**: Neutral, adversarial auditor who attempts to break the implementation:
  - Executes stress tests, boundary checks, and race condition tests.
  - Audits security filters, anti-leak projections, and database queries.
  - Runs full automated regression test suites.
- **Gatekeeper Sign-Off**:
  - The feature is marked **APPROVED** only when the QA Adversary confirms zero regressions, 100% test pass rate, and zero memory/performance leaks.
  - If issues are detected, the task returns to Phase 2 with explicit diagnostic failure details.

## Communication Standards
- Emit concise, meaningful milestone summaries at phase transitions.
- Emit a brief heartbeat if any single phase execution exceeds 5–10 minutes.
- Refrain from micro-spamming tool calls.
