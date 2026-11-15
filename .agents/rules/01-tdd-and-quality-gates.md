# Rule: Test-Driven Development (TDD) & Quality Gates

## Scope & Applicability
This rule applies to all core logic, algorithms, state machines, network transports, data mutation, and persistence layers across all supported platforms.

## Core Directives

### 1. Test-First Mindset
- Automated unit, integration, and boundary tests must be written BEFORE any production logic is introduced or modified.
- Tests must rigorously exercise edge and boundary conditions:
  - Empty, `null`, zero, negative, or malformed inputs.
  - Maximum data limits and buffer overflow scenarios.
  - Filesystem permission errors, missing directories, and concurrent access.
  - Network timeouts, simulated packet loss, and connection termination mid-transfer.

### 2. Regression Protection & Determinism
- Prior to committing or finalizing any feature, all project test suites must execute cleanly without failures.
- Tests must be completely deterministic:
  - No dependency on real wall-clock delays; use mock timers or deterministic virtual clocks where appropriate.
  - Isolate temporary directories with proper setup and teardown fixtures.
  - Seed random number generators when testing probabilistic algorithms.

### 3. Genuine Testing (No Dummy Tests)
- Every test must perform genuine assertions on returned data structures, internal state machines, or persistent files.
- Mocks are restricted to external system boundaries (network hardware, OS windows, platform-specific APIs). Real in-memory or temporary databases/engines are preferred to verify authentic runtime behavior.
- Test suites must maintain a 100% pass rate with zero flaky tests.
