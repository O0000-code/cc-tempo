# Claude Context Percentage

A Claude Code StatusLine command that displays context window usage percentage with a visual progress bar - matching Claude's official style.

## Features

- **Progress Bar Display** - Visual representation matching Claude official style
- **Accurate Algorithm** - Based on CCometixLine's proven implementation
- **Simple Mode** - Optional plain percentage output

## Output Formats

### Default (Progress Bar - Official Style)
```
Context: ████████████░░░░░░░░ 65%
```

### Simple Mode (`--simple`)
```
65%
```

## Algorithm

Based on [CCometixLine](https://github.com/Haleclipse/CCometixLine)'s context percentage algorithm:

1. **Parse** the transcript JSONL file
2. **Find** the last assistant message's usage data
3. **Calculate** context tokens: `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens`
4. **Compute** percentage: `(context_tokens / context_limit) * 100`

### Key Insight

The algorithm uses the **last assistant message's usage** (not cumulative sum) because Claude API's `input_tokens` already includes the full context.

## Installation

```bash
cd claude-context-percentage
npm install
npm run build
npm link
```

## Usage

### Standalone

```bash
# Progress bar (default)
echo '{"transcript_path":"/path/to/session.jsonl","model":{"id":"claude-opus-4-5"}}' | claude-context-percentage
# Output: Context: ████████████░░░░░░░░ 65%

# Simple percentage
echo '{"transcript_path":"/path/to/session.jsonl","model":{"id":"claude-opus-4-5"}}' | claude-context-percentage --simple
# Output: 65%
```

### In Claude Code StatusLine

Create `~/.claude/statusline.sh`:

```bash
#!/usr/bin/env bash
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CONTEXT_BAR=$(echo "$input" | claude-context-percentage 2>/dev/null || echo "Context: ░░░░░░░░░░░░░░░░░░░░ -")
echo "$MODEL | $CONTEXT_BAR | \$$(printf "%.2f" $COST)"
```

Configure `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/you/.claude/statusline.sh"
  }
}
```

### Result

```
Claude Opus 4.5 | Context: ███████████████░░░░░ 77% | $1.25
```

## Progress Bar Specification

| Element | Character | Unicode |
|---------|-----------|---------|
| Filled | █ | U+2588 (FULL BLOCK) |
| Empty | ░ | U+2591 (LIGHT SHADE) |
| Length | 20 characters | - |

## Context Limits

| Model Pattern | Context Limit |
|--------------|---------------|
| `[1m]` | 1,000,000 |
| `claude-*` (default) | 200,000 |
| `glm-4.5` | 128,000 |
| `kimi-k2*` | 128,000 |
| `qwen3-coder` | 256,000 |

## File Structure

```
claude-context-percentage/
├── src/
│   ├── index.ts        # Main entry point
│   ├── types.ts        # Type definitions
│   ├── parser.ts       # JSONL parsing & token calculation
│   ├── calculator.ts   # Percentage calculation + progress bar
│   ├── models.ts       # Model context limits
│   └── debug.ts        # Debug utility
├── package.json
├── tsconfig.json
└── README.md
```

## License

MIT
