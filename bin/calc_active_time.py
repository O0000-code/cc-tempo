#!/usr/bin/env python3
"""Calculate active work time from Claude Code transcript JSONL.
Outputs active_time_ms on stdout. Used by statusline.sh.

Active work time = sum of each human turn's wall-clock duration.
Excludes user idle time between turns.
Excludes wait time for interactive tools (e.g. AskUserQuestion, ExitPlanMode).
Parallel SubAgents don't inflate this (wall-clock only counts once).

Idle protections (only ever reduce time, never inflate):
- First-response gap: when the user's prompt and the first assistant entry are
  separated by more than MAX_IDLE_GAP_S, only count the last MAX_IDLE_GAP_S of
  that gap as active. Catches the case where the user stayed idle after
  submitting (e.g. session resumed days later) and Claude responds late.
- Stop-hook cap: when a `system` entry with `subtype=turn_duration` or
  `subtype=stop_hook_summary` appears within a turn (after Claude has produced
  at least one assistant entry), cap the effective turn end at that marker.
  Anything after these markers is post-turn idle (e.g. away_summary, queued
  prompts) even if subsequent gaps stay under MAX_IDLE_GAP_S.
- Tail extension: after the last in-range assistant entry, extend the active
  end forward only while inter-entry gaps remain below MAX_IDLE_GAP_S.
"""
import json, sys
from datetime import datetime, timedelta

# Interactive tools that require manual user action (their tool_result starts a new turn)
INTERACTIVE_TOOLS = {"AskUserQuestion", "ExitPlanMode"}

# system.subtype markers Claude Code emits at end-of-turn (StopHook fires)
TURN_END_MARKERS = {"stop_hook_summary", "turn_duration"}

MAX_IDLE_GAP_S = 300  # 5 minutes


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

        # Find turn start indices.
        # Turn boundaries: user text messages + interactive tool results.
        # Synthetic command entries (e.g. <local-command-stdout>) are kept as
        # boundaries here — they limit the span of "fake turns" so the
        # first-response-gap clip below can shrink them rather than letting
        # them merge with adjacent real turns.
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

        total_ms = 0
        for t, si in enumerate(starts):
            ei = starts[t + 1] - 1 if t + 1 < len(starts) else len(entries) - 1

            # Stop-hook cap: cap the effective turn end at the first
            # turn_duration / stop_hook_summary marker after seeing an
            # assistant entry. Markers before any assistant (e.g. orphaned
            # from a previous session) are ignored.
            ei_eff = ei
            seen_assistant = False
            for j in range(si, ei + 1):
                ej = entries[j]
                if ej.get("type") == "assistant":
                    seen_assistant = True
                    continue
                if (seen_assistant
                        and ej.get("type") == "system"
                        and ej.get("subtype") in TURN_END_MARKERS):
                    ei_eff = j
                    break

            start_ts = parse_ts(entries[si]["timestamp"])

            # Find the first and last assistant entries in the (possibly
            # capped) turn range.
            first_asst_idx = None
            last_asst_idx = si
            for j in range(si + 1, ei_eff + 1):
                if entries[j].get("type") == "assistant":
                    if first_asst_idx is None:
                        first_asst_idx = j
                    last_asst_idx = j

            # First-response-gap clip: when the gap between the user's prompt
            # and the first assistant entry exceeds MAX_IDLE_GAP_S, the user
            # was idle (e.g. session paused after a synthetic /exit, or user
            # stepped away mid-turn). Only credit MAX_IDLE_GAP_S of that gap.
            if first_asst_idx is not None:
                first_asst_ts = parse_ts(entries[first_asst_idx]["timestamp"])
                first_gap = (first_asst_ts - start_ts).total_seconds()
                if first_gap > MAX_IDLE_GAP_S:
                    start_ts = first_asst_ts - timedelta(seconds=MAX_IDLE_GAP_S)

            # Active end is at least the last assistant entry.
            if last_asst_idx > si:
                active_end_ts = parse_ts(entries[last_asst_idx]["timestamp"])
            else:
                active_end_ts = start_ts

            # Tail extension after the last assistant entry, gated by 5-min
            # gaps (catches final tool_results / stop markers but stops at
            # session-restoration / idle entries).
            if last_asst_idx < ei_eff:
                prev_ts = active_end_ts
                for j in range(last_asst_idx + 1, ei_eff + 1):
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
