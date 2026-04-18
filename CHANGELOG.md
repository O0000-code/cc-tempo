# Changelog

All notable changes to cc-tempo will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-04-18

Initial public release.

### Added
- **Line 1 — session metrics**: total tokens (K/M formatted), cost (USD), 20-char context progress bar, cache hit rate, active work time, SubAgent speedup ratio.
- **Line 2 — git development** (only in git repos): current branch, multi-instance detection (`N active`), diff stats, `lines/$` efficiency, 8-char code-churn quality sparkline with trend arrow.
- **Line 3 — account rate limits** (only when the `rate_limits` field is present in stdin JSON): 5h and 7d usage gauges with reset countdowns.
- **Active work time** parsed from transcript JSONL; excludes user idle and waits for interactive tools (`AskUserQuestion`, `ExitPlanMode`).
- **State persistence across `/clear`** within the same Claude process via PID-based `/tmp` files.
- **Sparkline zero-separate + log2 min-max normalization** for meaningful visualization across a wide dynamic range.
- **`install.sh` / `uninstall.sh`** — one-command install and full cleanup.
- **Bundled `claude-context-percentage` TypeScript CLI** for accurate context-percentage calculation from transcript parsing (used as a more reliable source than the hook JSON's pre-computed `used_percentage`).

### Dependencies
`jq`, `bc`, `python3 >= 3.8`, `Node.js >= 18`, `git`.
