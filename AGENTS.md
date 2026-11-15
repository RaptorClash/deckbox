# Project Agent Guidelines & Quality Standards

This repository adheres to the PokéVault Development Standard: strict Test-Driven Development (TDD), adversarial quality gates, 3-role multi-agent committee workflow, 3-branch Git release management, and multi-language support.

---

## ⚡ Mandatory Development & Workflow Protocol

All agents and contributors must strictly comply with the following 5 rules:

### 1. Focused Status Updates & Heartbeat (No Micro-Spam)
- **Do not send micro-updates for individual tool calls**: Execute work cleanly and concisely without flooding the conversation.
- **Heartbeat for long tasks**: If an operation (build, test run, translation) runs for more than 5–10 minutes, emit a short, informative status update so the user knows the process is running smoothly.
- **Milestone communication**: Comprehensive status reports are reserved for phase changes and final verification.

### 2. Strict TDD (Test-Driven Development — Tests First!)
- **Zero production code before tests**: Never modify or add code in production directories (e.g. `core/`, `lib/`, `src/`) before corresponding unit or integration tests exist in `test/`.
- **Workflow**:
  1. **Red**: Write tests covering required behavior and edge cases (must fail before implementation).
  2. **Green**: Write minimal, clean production code to pass all tests.
  3. **Refactor**: Clean up and optimize while preserving 100% test pass rate.

### 3. Adversarial Testing & Boundary Hardening
- Do not test only happy paths. Features must be hardened against:
  - Empty, null, zero, negative, and invalid parameters.
  - Maximum data volumes, buffer limits, and memory pressure.
  - Asynchronous timing, race conditions, and disconnects.
  - State desynchronization, packet loss, and error recovery.

### 4. UI Visual Alignment & Prototyping
- **Explicit Rule for DeckBox**: UI is built directly in Godot 4 and `web_lite/` without pre-built HTML mockups in `docs/prototypes/`. Direct visual styling within engine scenes, themes, and web components is fully approved and encouraged.
- Interactive testing occurs directly through Godot scenes and `web_lite/index.html`.

### 5. Zero-Tolerance Quality Gate
- A task is considered complete ONLY when:
  1. All test suites pass with **100% pass rate** (0 failures, 0 errors).
  2. All linters and analyzers report **0 errors, 0 warnings**.

---

## Detailed Rules Directory (`.agents/rules/`)

1. **`01-tdd-and-quality-gates.md`**: Test-first rules, deterministic fixtures, boundary cases, and zero dummy tests.
2. **`02-database-and-persistence.md`**: Portable data directories, non-destructive updates, idempotent migrations (`_addColumnIfNotExists`), and downgrade safety.
3. **`03-multi-agent-committee-workflow.md`**: 3-Phase Committee: Test Architect → Core Developer → QA Adversary & Sign-Off Gatekeeper.
4. **`04-cross-platform-and-sync-resilience.md`**: Cross-platform path normalization, forward/backward schema tolerance, and field-level patch merge.
