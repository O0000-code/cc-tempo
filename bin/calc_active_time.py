#!/usr/bin/env python3
"""Calculate active work time from Claude Code transcript JSONL.
Outputs active_time_ms on stdout. Used by statusline.sh.

Active work time = sum of each human turn's wall-clock duration.
Excludes user idle time between turns.
Excludes wait time for interactive tools (e.g. AskUserQuestion, ExitPlanMode).
Parallel SubAgents don't inflate this (wall-clock only counts once).
"""
import json, sys
from datetime import datetime

# Interactive tools that require manual user action
INTERACTIVE_TOOLS = {"AskUserQuestion", "ExitPlanMode"}


def parse_ts(s):
    return datetime.fromisoformat(s.rstrip('Z'))


def find_interactive_tool_use_ids(entries):
    """Find tool_use_id of all interactive tool calls from assistant messages."""
    ids = set()
    for d in entries:
        if d.get("type") == "assistant":
            content = d.get("message", {}).get("content", [])
            if isinstance(content, list):
                for block in content:
                    if (isinstance(block, dict)
                            and block.get("type") == "tool_use"
                            and block.get("name") in INTERACTIVE_TOOLS):
                        ids.add(block.get("id"))
    return ids


def is_interactive_tool_result(entry, interactive_ids):
    """Check if a user entry is a tool_result for an interactive tool."""
    content = entry.get("message", {}).get("content", [])
    if not isinstance(content, list):
        return False
    for block in content:
        if (isinstance(block, dict)
                and block.get("type") == "tool_result"
                and block.get("tool_use_id") in interactive_ids):
            return True
    return False


def main():
    if len(sys.argv) < 2:
        print("0")
        return
    try:
        entries = []
        with open(sys.argv[1]) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                    if d.get("timestamp"):
                        entries.append(d)
                except (json.JSONDecodeError, KeyError):
                    continue

        if len(entries) < 2:
            print("0")
            return

        interactive_ids = find_interactive_tool_use_ids(entries)

        # Find turn start indices
        # Turn boundaries: user text messages + interactive tool results
        starts = []
        for i, d in enumerate(entries):
            if d.get("type") == "user":
                m = d.get("message", {})
                if m.get("role") == "user":
                    if isinstance(m.get("content", ""), str):
                        starts.append(i)
                    elif is_interactive_tool_result(d, interactive_ids):
                        starts.append(i)

        if not starts:
            print("0")
            return

        # Sum each turn's wall-clock duration.
        # Hybrid idle-detection: trust all gaps up to the last assistant
        # entry (covers SubAgent / long tool execution), then apply gap
        # detection in the tail to exclude session-restoration entries.
        MAX_IDLE_GAP_S = 300  # 5 minutes

        total_ms = 0
        for t, si in enumerate(starts):
            ei = starts[t + 1] - 1 if t + 1 < len(starts) else len(entries) - 1
            start_ts = parse_ts(entries[si]["timestamp"])

            # Find the last assistant entry in this turn's range
            last_asst_idx = si
            for j in range(si, ei + 1):
                if entries[j].get("type") == "assistant":
                    last_asst_idx = j

            # Active end is at least the last assistant entry
            if last_asst_idx > si:
                active_end_ts = parse_ts(
                    entries[last_asst_idx]["timestamp"])
            else:
                active_end_ts = start_ts

            # After the last assistant entry, include subsequent entries
            # only while gaps remain small (catches final tool_results
            # but stops at restoration/idle entries)
            if last_asst_idx < ei:
                prev_ts = active_end_ts
                for j in range(last_asst_idx + 1, ei + 1):
                    ts = parse_ts(entries[j]["timestamp"])
                    if (ts - prev_ts).total_seconds() > MAX_IDLE_GAP_S:
                        break
                    active_end_ts = ts
                    prev_ts = ts

            dur = (active_end_ts - start_ts).total_seconds()
            if dur > 0:
                total_ms += int(dur * 1000)

        print(total_ms)
    except Exception:
        print("0")


if __name__ == "__main__":
    main()
