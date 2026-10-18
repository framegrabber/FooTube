# Constraints

Last reviewed: 2026-10-19 by @felix

Read this file before writing code. Do not weaken it to make a change pass. Every check below **blocks**: a task is not done until `scripts/check.sh task` exits 0.

## Floor (always enforced)

Checked by `node scripts/floor-guard.mjs` on the diff against `main` (or `origin/main` once a remote exists), including untracked files. Paths in `.constraintsignore` skip the pattern checks; each must be an Exceptions row below.

- No new suppressions: `swiftlint:disable`, `swiftformat:disable`, `gitleaks:allow`, `nosemgrep`, `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `-suppress-warnings`, `SWIFT_TREAT_WARNINGS_AS_ERRORS: NO`
- No unfinished work: `TODO`, `FIXME`, `fatalError`/`preconditionFailure` with "not implemented"/"unimplemented", empty `catch {}`
- No easier tests: no added `.disabled` trait, `withKnownIssue`, `XCTSkip`; no deleted test files; no `#expect`/`#require`/`XCTAssert` removed from a test file that stays
- No secrets, cookies or tokens in source
- This file does not get weakened to make a change pass

## Enforced

| Dimension | Rule | Checked by | Runs at |
|-----------|------|-----------|---------|
| Floor | Zero findings | `node scripts/floor-guard.mjs` | every edit (fast), task end |
| Format | Zero diffs from `.swiftformat` | `swiftformat --lint .` | every edit (fast), task end |
| Secrets | Zero findings in our sources, redacted output (`.gitleaks.toml` excludes only build outputs and SwiftPM checkouts) | `gitleaks dir --redact --no-banner .` | every edit (fast), task end |
| Warnings: core | Zero compiler warnings in our targets (Swift 6 language mode, warnings are errors via `Package.swift` settings) | `swift build --package-path Packages/FooTubeCore` | task end |
| Tests: core | All offline tests pass | `swift test --package-path Packages/FooTubeCore` | task end |
| Warnings: app | Zero compiler warnings in the app target (`SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`, `SWIFT_VERSION: 6`) | `xcodebuild … -destination 'platform=tvOS Simulator,name=Apple TV' build` | task end |
| Dependencies | No known vulnerability at severity high or above | `osv-scanner scan source -r .` on `Package.resolved` | task end |

Why these numbers: zero is the only stable value for warnings, format and secrets (a non-zero budget gets spent). "High or above" for dependencies because lower findings are mostly noise for a private, single-user app; FFmpeg builds (if MPVKit is added) routinely carry unfixable low/medium findings.

External opinions in this bar: the Swift compiler, gitleaks rules, and the OSV vulnerability database.

## Budget

- `scripts/check.sh fast` (floor, format, secrets): a few seconds; run after edits.
- `scripts/check.sh task` (everything): about 90 s with an incremental Simulator build; run before handing a task back.

## Measured, not yet enforced

| Metric | Today | Direction |
|--------|-------|-----------|
| (none yet) | | |

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|----|------|------|--------|-------|---------|
| E1 | Floor pattern checks (TODO/FIXME, suppressions) | `Packages/InnerTubeKit/**` | Vendored upstream b5i/YouTubeKit, kept unmodified so updates stay mechanical (`VENDORED.md`); listed in `.constraintsignore` | @felix | 2027-01-17 |
