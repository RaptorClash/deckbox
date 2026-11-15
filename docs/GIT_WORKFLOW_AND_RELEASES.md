# Git Branching Model & Release Pipeline Guide

This document defines the standard Git branching strategy, branch protection rules, versioning protocols, and automated release pipelines for projects adopting the PokéVault Development Standard.

---

## 1. The Branching Model

A structured **Release Branching Strategy** is used across all projects:

```
main (Production) -----------------------------------------------------[Release Tag v0.1.0]
     \                                                                 /
      \--- release/0.1.0 (Staging & Stabilization) -------------------/
               \                                  /
                \--- feature/0.1.0-foundation ---/
```

### The 4 Branch Categories:

| Branch Type | Pattern | Purpose & Access Control |
| :--- | :--- | :--- |
| **Production** | `main` | **Protected**. Contains exclusively stable, published release code. Every merge into `main` corresponds to an official release. Direct pushes are disabled. |
| **Release / Staging** | `release/<version>` (e.g. `release/0.1.0`) | Staging branch for all features targeted for a release. Integration testing, beta builds, and stabilization occur here. |
| **Feature Branches** | `feature/<version>-<topic>` | Short-lived branches for individual components. Branch off the relevant `release/*` branch and merge back via Pull Request. |
| **Hotfixes** | `hotfix/<version>` | Emergency patches for production bugs. Branch off `main` and merge into both `main` and active `release/*` branches. |

---

## 2. GitHub Branch Protection Setup

To safeguard code quality, configure branch protection rules in GitHub (**Settings** $\rightarrow$ **Branches**):

### Protection for `main`:
- **Branch pattern**: `main`
- [x] **Require a pull request before merging**
- [x] **Require status checks to pass before merging**
  - Select CI jobs: `Python Release Tools & Pipeline Tests` and `Project Test Suite & Quality Gate`
- [x] **Require branches to be up to date before merging**
- [x] **Do not allow bypassing the above settings**

### Protection for `release/*`:
- **Branch pattern**: `release/*`
- [x] **Require status checks to pass before merging**

---

## 3. Daily Developer Workflow

### Step 1: Create a Feature Branch
Always branch from the active release branch:
```bash
git checkout release/0.1.0
git pull origin release/0.1.0
git checkout -b feature/0.1.0-table-assets
```

### Step 2: Strict Test-Driven Development (TDD)
1. **Tests First**: Author automated unit tests in `test/` verifying requirements and edge cases.
2. **Implement**: Write minimal production code to turn tests green.
3. **Verify**:
   ```bash
   python -m unittest discover -s test/tool
   # Run project test command (e.g. godot_console, flutter test, npm test)
   ```

### Step 3: Commit & Push
```bash
git add .
git commit -m "feat(table): add arcade 3D table shaders and meshes"
git push -u origin feature/0.1.0-table-assets
```

---

## 4. Release Automation

### Step 1: Bump Version
Use the multi-stack version bumper:
```bash
# Preview changes
python tool/bump_version.py 0.1.0 --dry-run

# Execute bump and tag
python tool/bump_version.py 0.1.0 --commit --tag
```

### Step 2: Generate Multi-Language Release Notes
Draft your release notes in `RELEASE_NOTES_DRAFT.md` and generate the 13-language collapsible output:
```bash
python tool/translate_release_notes.py RELEASE_NOTES_DRAFT.md -o RELEASE_NOTES.md
```

### Step 3: Merge Release to Main
Create a Pull Request from `release/0.1.0` into `main`. Once merged, GitHub Actions will automatically evaluate the release gate, build target binaries, and publish the official GitHub Release with multi-language release notes.
