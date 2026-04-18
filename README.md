# cc-tempo

A Claude Code statusline that shows not just how much you've used, but how fast you're working.

```
49.7M tokens · $29.46 | Context: ████████████░░░░░░░░ 60% | Cached 85% · ⏱ 2h 15m [1.8×]
───
main · 2 active | +156 -23 · 12 files · 89 lines/$ | Quality: ▁▁▂▃▅▆▇█ ↑
───
Limits: 5h ▮▮▮▮▮▮▮▮▯▯ 87% · 7d ▮▮▮▮▮▮▮▯▯▯ 71% | ↻ 47m · 2d 3h
```

## Why cc-tempo

Most Claude Code statuslines answer *"how much have I spent?"* Tokens, cost, context — the accounting view. cc-tempo adds the *tempo* view: how actively are you working, how much parallelism are your SubAgents actually giving you, and is your coding pace picking up or slowing down. Five things set it apart from other statuslines on GitHub:

- **Active work time from the transcript, not `total_api_duration_ms`.** `⏱ 2h 15m` is parsed turn-by-turn out of the session JSONL. It's the wall-clock time you were actually working — user idle gaps are excluded, and interactive tools (`AskUserQuestion`, `ExitPlanMode`) don't count because they're waiting on you, not on the model. Cumulative API duration inflates under parallel SubAgents; this doesn't.
- **Speedup ratio `[1.8×]`.** API cumulative time ÷ active wall-clock time. Shown only when the ratio reaches 1.2 or higher, so when you see it, you're getting real parallelism out of your SubAgents. When it's hidden, you're not — and you'll know to reach for fan-out.
- **Persist across `/clear`.** The timer is keyed by the ancestor `claude` process PID in `/tmp`, so `/clear` inside the same session does not reset the clock. A brand-new `claude` invocation starts fresh. `claude --continue` inherits the dead PID's accumulated total.
- **Quality sparkline for code-change velocity.** `▁▁▂▃▅▆▇█ ↑` tracks added+removed lines per statusline tick, not token burn. Zero-separate + log2 min-max normalization keeps it readable whether you're making 5-line or 500-line edits. With three or more data points you also get a trend arrow comparing first-half to second-half mean.
- **Multi-instance detection.** `2 active` surfaces when you have two or more `claude` processes running on the same project directory, so you see when a worktree or a parallel session is live.

At a glance:

| Dimension | What other statuslines typically show | What cc-tempo shows |
|---|---|---|
| Session time | `cost.total_api_duration_ms` | Wall-clock active time from transcript turns |
| Parallelism | — | `[N.N×]` speedup ratio when ≥ 1.2 |
| `/clear` handling | Counter resets | Accumulator persists inside the same `claude` PID |
| Code-change pace | — | 8-char sparkline + trend arrow over last 8 ticks |
| Concurrent sessions | — | `N active` when two or more instances share a project |

## Features

The output is three stdout lines. Line 1 always renders. Line 2 renders only inside a git repo. Line 3 renders only when Claude Code's stdin JSON includes `rate_limits` (subscriber accounts).

### Line 1 — Session

Always on.

```
49.7M tokens · $29.46 | Context: ████████████░░░░░░░░ 60% | Cached 85% · ⏱ 2h 15m [1.8×]
```

Early in a session — before the first API response — it looks like this:

```
0 tokens · $0.00 | Context: ░░░░░░░░░░░░░░░░░░░░ - | ⏱ <1m
```

Fields:

| Field | Source | Notes |
|---|---|---|
| `49.7M tokens` | `claude-context-percentage --tokens`, with a `jq` fallback | Totals input + output + cache-read + cache-create. K/M suffix. |
| `$29.46` | `cost.total_cost_usd` | Two-decimal dollar amount. |
| `Context: [bar] 60%` | `context_window.used_percentage` | 20-char bar of `█`/`░`. Null-state renders `░░…░ -`. |
| `Cached 85%` | `context_window.current_usage.*` | Hidden entirely when `current_usage` is absent or totals zero. |
| `⏱ 2h 15m` | transcript JSONL via `calc_active_time.py` | Under one minute shows `⏱ <1m`; rolls up to `Xh`, `Xh Ym`. |
| `[1.8×]` | `API_DURATION_MS ÷ ACTIVE_MS` | Integer math on `×10`. Shown only when the ratio is `≥ 1.2`. |

### Line 2 — Development

Renders only when `workspace.project_dir` is inside a git worktree. Prefixed by a `───` separator.

```
main · 2 active | +156 -23 · 12 files · 89 lines/$ | Quality: ▁▁▂▃▅▆▇█ ↑
```

With no uncommitted changes:

```
feature-x | clean | Quality: ▁▁▁▁▁▁▁▁
```

Fields:

| Field | Source | Notes |
|---|---|---|
| `main` | `git branch --show-current` | Branch name. |
| `· 2 active` | `pgrep` of `claude` processes scoped to `project_dir` | Appears only when two or more instances are live. |
| `+156 -23 · 12 files` | `git diff --numstat HEAD` | Replaced by `clean` when nothing is staged or unstaged. |
| `89 lines/$` | `(added+removed) ÷ total_cost_usd` | Shown only when total cost is at least 50¢. Pure-bash integer math. |
| `Quality: ▁▁▂▃▅▆▇█ ↑` | per-tick delta history in `/tmp/statusline-spark-{session_id}` | See below. |

**Sparkline details.** Eight characters wide, always. Each tick, cc-tempo records `total_lines_added + total_lines_removed` and stores up to the last eight deltas. Normalization:

- No data yet → `▁▁▁▁▁▁▁▁` (the initial state you see on a fresh session).
- All zeros → same flat `▁▁▁▁▁▁▁▁`.
- Otherwise zero values map to `▂` (area-chart baseline), and non-zero values go through integer `log2` then min-max normalization into `▃` through `█`. If every non-zero value shares the same `log2` bucket, an absolute-scale fallback (5 / 15 / 40 / 100 / 250 line thresholds) takes over.

**Trend arrow** (`↑` / `↓` / `→`). Appears only with three or more data points. Compares the mean of the first half of the window against the mean of the second half. A ±20% swing flips the arrow.

### Line 3 — Account rate limits

Renders only when Claude Code's stdin JSON includes `rate_limits.*.used_percentage` (subscriber accounts surface these; others don't). Prefixed by a `───` separator.

```
Limits: 5h ▮▮▮▮▮▮▮▮▯▯ 87% · 7d ▮▮▮▮▮▮▮▯▯▯ 71% | ↻ 47m · 2d 3h
```

Fields:

| Field | Source | Notes |
|---|---|---|
| `5h ▮…▯ 87%` | `rate_limits.five_hour.used_percentage` | 10-char gauge using `▮`/`▯`. |
| `7d ▮…▯ 71%` | `rate_limits.seven_day.used_percentage` | Same gauge style. |
| `↻ 47m · 2d 3h` | `*.resets_at` (epoch seconds) | Countdown per window. Order matches the gauge order. When only one window has a reset but both have gauges, the label disambiguates (`↻ 5h: 47m`). |

If a window has a gauge but no reset timestamp, only the gauge renders — no `↻` segment is emitted for it.

## Install

**Prerequisites:** `jq`, `bc`, `python3` (3.8 or newer), `Node.js` (18 or newer), `git`.

On macOS, system deps are a one-liner: `brew install jq bc`.

```bash
git clone https://github.com/O0000-code/cc-tempo.git
cd cc-tempo
./install.sh
```

`install.sh` does three things:

1. Copies `bin/statusline.sh` and `bin/calc_active_time.py` into `~/.claude/`, preserving their side-by-side layout (they discover each other via `SCRIPT_DIR`, so keep them co-located).
2. Builds `tools/context-percentage/` and installs the `claude-context-percentage` CLI globally via `npm install -g`. The bash script's `--tokens` path depends on it; the `jq` fallback handles the case where it's missing, but token counts are less accurate.
3. Prints the `statusLine` snippet you need to paste into `~/.claude/settings.json`.

## Configure

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 2
  }
}
```

`padding` is optional and controls horizontal spacing around the rendered line. Default is `0`.

## Verify

Pipe a minimal JSON payload through the installed script to confirm it renders:

```bash
echo '{"context_window":{"used_percentage":60,"total_input_tokens":1000,"total_output_tokens":500},"cost":{"total_cost_usd":1.50,"total_api_duration_ms":5000},"workspace":{"project_dir":"'"$PWD"'"},"session_id":"smoke-test"}' \
  | bash ~/.claude/statusline.sh
```

You should see Line 1 at minimum, and Line 2 if `$PWD` is inside a git repo. The active-time algorithm can also be invoked directly for a known transcript:

```bash
python3 ~/.claude/calc_active_time.py /path/to/transcript.jsonl
```

Its stdout is a single integer — milliseconds of active work in that transcript.

## How it works

**Protocol.** Claude Code runs the configured command after each assistant reply and pipes a JSON payload over stdin. The command writes its output to stdout, which becomes the terminal status bar. Updates are debounced at 300 ms and the script is killed if a newer tick arrives before it finishes — so every branch of `statusline.sh` is written to be fast and side-effect-light.

**Components.**

- `bin/statusline.sh` reads stdin, assembles up to three lines, and writes them to stdout. It shells out to `jq` for JSON extraction, `bc` only where the `TOKENS` CLI is unavailable, and pure-bash integer math everywhere else.
- `bin/calc_active_time.py` takes the transcript JSONL path as its only argument and prints active milliseconds. Turn boundaries are user text messages or tool-results for interactive tools. Each turn's duration runs from its start timestamp to the last assistant timestamp in range, then extends forward through subsequent entries only while inter-entry gaps stay under 5 minutes — this captures trailing `tool_result`s but stops cleanly at session-restore entries and idle gaps.
- `tools/context-percentage/` is a small TypeScript CLI (`claude-context-percentage`) that parses the transcript JSONL directly. Claude Code's stdin JSON sometimes omits `used_percentage`, and its `total_*_tokens` fields can undercount cache usage on some paths, so the CLI re-derives both from the last assistant message's `usage` record. Model context limits are pattern-matched (`[1m]` → 1M, generic `claude-*` → 200K, plus third-party models).

**Persistence.** Two `/tmp` files hold per-session state: `statusline-time-{project_hash}.{claude_pid}` for the active-time accumulator, and `statusline-spark-{session_id}` for sparkline delta history. Both are cleaned up when their owning Claude process dies. The time file is inherited when a new session shares the old `session_id` — that's how `claude --continue` keeps its clock.

**Repo layout.**

```
cc-tempo/
├── bin/
│   ├── statusline.sh        # Main script — reads stdin, writes up to 3 lines
│   └── calc_active_time.py  # Active-time algorithm (stdin-free, takes transcript path)
├── tools/
│   └── context-percentage/  # TypeScript CLI, installed globally as claude-context-percentage
├── install.sh
├── uninstall.sh
└── settings.example.json
```

## Uninstall

```bash
./uninstall.sh
```

Removes the installed scripts, uninstalls the global `claude-context-percentage` CLI, and reminds you to strip the `statusLine` stanza from `~/.claude/settings.json`.

## Credits

The context-percentage algorithm is adapted from [CCometixLine](https://github.com/Haleclipse/CCometixLine) — using the last assistant message's `usage` record rather than a cumulative sum, because Anthropic's `input_tokens` already reflects the full conversation.

## License

[MIT](LICENSE) © 2026 [O0000-code](https://github.com/O0000-code)
