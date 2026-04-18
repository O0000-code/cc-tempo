# cc-tempo

> A Claude Code statusline that shows not just how much you've used, but how fast you're working.

```
49.7M tokens · $29.46 | Context: ████████████░░░░░░░░ 60% | Cached 85% · ⏱ 2h 15m [1.8×]
───
main · 2 active | +156 -23 · 12 files · 89 lines/$ | Quality: ▁▁▂▃▅▆▇█ ↑
───
Limits: 5h ▮▮▮▮▮▮▮▮▯▯ 87% · 7d ▮▮▮▮▮▮▮▯▯▯ 71% | ↻ 47m · 2d 3h
```

## Why cc-tempo

Other statuslines show *how much*. cc-tempo also shows *how fast*:

- **⏱ Active work time** — real wall-clock work time (parsed from transcript), not inflated `api_duration_ms`
- **[1.8×] Speedup ratio** — shown when SubAgents give you ≥ 1.2× parallel gain
- **/clear-resilient timer** — persists inside the same `claude` process; a new `claude` invocation resets cleanly
- **Quality sparkline `▁▂▃▅▆▇█ ↑`** — code-change velocity over the last 8 ticks, with trend arrow
- **Multi-instance `2 active`** — concurrent `claude` sessions on the same project directory

## Layout

| Line | When it renders | Contents |
|---|---|---|
| 1 | always | `tokens · $cost · context bar · cache% · ⏱ time · [speedup]` |
| 2 | inside a git repo | `branch · N active · diff · lines/$ · quality sparkline` |
| 3 | when `rate_limits` is in stdin | `5h gauge · 7d gauge · ↻ countdowns` |

## Install

**Prereqs**: `jq` · `bc` · `python3 ≥ 3.8` · `Node.js ≥ 18` · `git` (macOS: `brew install jq bc`)

```bash
git clone https://github.com/O0000-code/cc-tempo.git
cd cc-tempo
./install.sh
```

Add to `~/.claude/settings.json`, then restart Claude Code:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 2
  }
}
```

## Uninstall

```bash
./uninstall.sh
```

## Credits

Context-percentage algorithm adapted from [CCometixLine](https://github.com/Haleclipse/CCometixLine).

## License

[MIT](LICENSE) © 2026 [O0000-code](https://github.com/O0000-code)
