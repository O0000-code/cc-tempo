#!/usr/bin/env bash
# Claude Code StatusLine - Enhanced Version
# Format: 49.7M tokens · $29.46 | Context: [progress bar] XX% | ⏱ Xh Ym · Cached XX%
#
# Features:
# - Token usage with "tokens" suffix + Cost combined with · separator
# - Context progress bar in the middle (visual focus)
# - Session duration with ⏱ indicator (active work time from transcript)
# - Parallel speedup ratio with ⏩ indicator (when SubAgent parallelization detected)
# - Cache hit rate from current_usage (hidden when no cache data)
# - No model name display

input=$(cat)

# ============================================================
# 1. Context Progress Bar (using official used_percentage)
# ============================================================
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

if [[ -z "$PCT" || "$PCT" == "null" ]]; then
  # Null state: no API call yet → all empty bar + dash
  CONTEXT_BAR="Context: ░░░░░░░░░░░░░░░░░░░░ -"
else
  # Clamp to 0-100 and round to integer
  PCT_INT=$(printf "%.0f" "$PCT")
  (( PCT_INT < 0 )) && PCT_INT=0
  (( PCT_INT > 100 )) && PCT_INT=100

  # Render 20-char progress bar
  FILLED=$((PCT_INT * 20 / 100))
  EMPTY=$((20 - FILLED))
  BAR=""
  [ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | tr ' ' '█')
  [ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | tr ' ' '░')"

  CONTEXT_BAR="Context: $BAR $PCT_INT%"
fi

# ============================================================
# 2. Token Usage (complete: input + output + cache_creation + cache_read)
# Uses claude-context-percentage --tokens for accurate calculation
# Falls back to Hook Data if command fails
# ============================================================
TOKENS_FMT=$(echo "$input" | claude-context-percentage --tokens 2>/dev/null)

# Fallback to Hook Data if --tokens fails or returns placeholder
if [[ -z "$TOKENS_FMT" || "$TOKENS_FMT" == "-" ]]; then
  INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
  OUTPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

  # Handle null values
  [[ "$INPUT_TOKENS" == "null" ]] && INPUT_TOKENS=0
  [[ "$OUTPUT_TOKENS" == "null" ]] && OUTPUT_TOKENS=0

  # Calculate total tokens
  TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))

  # Format tokens with K/M suffix
  format_tokens() {
    local tokens=$1
    if (( tokens >= 1000000 )); then
      # Millions: 1.2M
      local m_value=$(echo "scale=1; $tokens / 1000000" | bc)
      # Remove trailing .0 if present
      if [[ "$m_value" == *.0 ]]; then
        m_value=${m_value%.0}
      fi
      echo "${m_value}M"
    elif (( tokens >= 1000 )); then
      # Thousands: 125K
      local k_value=$(echo "scale=0; $tokens / 1000" | bc)
      echo "${k_value}K"
    else
      # Less than 1000: show as is
      echo "$tokens"
    fi
  }

  TOKENS_FMT=$(format_tokens $TOTAL_TOKENS)
fi

# ============================================================
# 3. Cost (from official hook data)
# ============================================================
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Handle null values
[[ "$COST" == "null" ]] && COST=0

# Format cost as $X.XX
COST_FMT=$(printf "\$%.2f" "$COST")

# ============================================================
# 4. Session Duration (active work time + parallel speedup ratio)
# Shows active work time from transcript JSONL (excludes user idle).
# Shows ⏩N.N speedup ratio when SubAgent parallelization detected.
# Falls back to cumulative API time if transcript unavailable.
# ============================================================
API_DURATION_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
[[ "$API_DURATION_MS" == "null" || -z "$API_DURATION_MS" ]] && API_DURATION_MS=0

# Calculate active work time from transcript JSONL
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIVE_MS=0
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // empty')
# Fallback: construct path from project_dir + session_id
if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  _PROJ=$(echo "$input" | jq -r '.workspace.project_dir // empty')
  _SID=$(echo "$input" | jq -r '.session_id // empty')
  if [[ -n "$_PROJ" && -n "$_SID" ]]; then
    _PHASH=$(echo "$_PROJ" | sed 's/[^a-zA-Z0-9]/-/g')
    TRANSCRIPT_PATH="$HOME/.claude/projects/${_PHASH}/${_SID}.jsonl"
  fi
fi
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  ACTIVE_MS=$(python3 "$SCRIPT_DIR/calc_active_time.py" "$TRANSCRIPT_PATH" 2>/dev/null)
fi
[[ -z "$ACTIVE_MS" || "$ACTIVE_MS" == "null" ]] && ACTIVE_MS=0

# --- Accumulate active time across /clear (session changes) ---
# Persisted in /tmp keyed by project hash + Claude PID.
# Same PID = same conversation (survives /clear).
# Different PID = new conversation (resets to 0).
# File format: {total_active_ms}\t{session_id}\t{session_active_ms}

# Find ancestor Claude Code process PID (stable across /clear, unique per conversation)
_find_claude_pid() {
  local _p=$PPID
  while [[ "$_p" != "1" && -n "$_p" && "$_p" != "0" ]]; do
    local _c
    _c=$(ps -o comm= -p "$_p" 2>/dev/null)
    if [[ "$_c" == */claude ]]; then
      echo "$_p"
      return
    fi
    _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')
  done
}

_TIME_PROJ=$(echo "$input" | jq -r '.workspace.project_dir // empty')
_TIME_SID=$(echo "$input" | jq -r '.session_id // empty')
if [[ -n "$_TIME_PROJ" && -n "$_TIME_SID" ]]; then
  _TIME_PHASH=$(echo "$_TIME_PROJ" | sed 's/[^a-zA-Z0-9]/-/g')
  _CLAUDE_PID=$(_find_claude_pid)

  if [[ -n "$_CLAUDE_PID" ]]; then
    # PID-based key: isolates each conversation, survives /clear
    _TIME_FILE="/tmp/statusline-time-${_TIME_PHASH}.${_CLAUDE_PID}"
    # Handle stale persist files: inherit on --continue, then clean up
    for _stale in /tmp/statusline-time-"${_TIME_PHASH}".*; do
      [[ -f "$_stale" ]] || continue
      _stale_pid="${_stale##*.}"
      [[ "$_stale_pid" =~ ^[0-9]+$ ]] || continue
      [[ "$_stale_pid" == "$_CLAUDE_PID" ]] && continue
      if ! kill -0 "$_stale_pid" 2>/dev/null; then
        # Before deleting, check for --continue: inherit if session matches
        if [[ ! -f "$_TIME_FILE" ]]; then
          IFS=$'\t' read -r _s_total _s_sid _s_sess < "$_stale"
          if [[ "$_s_sid" == "$_TIME_SID" ]]; then
            printf '%s\t%s\t%s\n' "${_s_total:-0}" "$_s_sid" "${_s_sess:-0}" > "$_TIME_FILE" 2>/dev/null
          fi
        fi
        rm -f "$_stale"
      fi
    done
    # Clean up legacy persist file (no PID suffix)
    rm -f "/tmp/statusline-time-${_TIME_PHASH}" 2>/dev/null
  else
    # Fallback: project-only key (legacy behavior)
    _TIME_FILE="/tmp/statusline-time-${_TIME_PHASH}"
  fi

  _RAW_ACTIVE=$ACTIVE_MS

  _PREV_TOTAL=0 _PREV_SID="" _PREV_SESS=0
  if [[ -f "$_TIME_FILE" ]]; then
    IFS=$'\t' read -r _PREV_TOTAL _PREV_SID _PREV_SESS < "$_TIME_FILE"
    [[ "$_PREV_TOTAL" =~ ^[0-9]+$ ]] || _PREV_TOTAL=0
    [[ "$_PREV_SESS" =~ ^[0-9]+$ ]] || _PREV_SESS=0
  fi

  if [[ "$_TIME_SID" == "$_PREV_SID" ]]; then
    # Same session: replace old session's contribution with current
    ACTIVE_MS=$(( _PREV_TOTAL - _PREV_SESS + _RAW_ACTIVE ))
  else
    # Session changed (/clear): carry forward accumulated total
    ACTIVE_MS=$(( _PREV_TOTAL + _RAW_ACTIVE ))
  fi
  (( ACTIVE_MS < 0 )) && ACTIVE_MS=0

  printf '%s\t%s\t%s\n' "$ACTIVE_MS" "$_TIME_SID" "$_RAW_ACTIVE" > "$_TIME_FILE" 2>/dev/null
fi

# Use active time if available, otherwise fall back to API duration
if (( ACTIVE_MS > 0 )); then
  DURATION_MS=$ACTIVE_MS
else
  DURATION_MS=$API_DURATION_MS
fi

DURATION_SEC=$((DURATION_MS / 1000))
HOURS=$((DURATION_SEC / 3600))
MINS=$(((DURATION_SEC % 3600) / 60))

if (( HOURS > 0 && MINS > 0 )); then
  DURATION_FMT="⏱ ${HOURS}h ${MINS}m"
elif (( HOURS > 0 )); then
  DURATION_FMT="⏱ ${HOURS}h"
elif (( MINS > 0 )); then
  DURATION_FMT="⏱ ${MINS}m"
else
  DURATION_FMT="⏱ <1m"
fi

# Parallel speedup ratio: [N.N×] (shown only when ratio >= 1.2)
SPEEDUP_FMT=""
if (( API_DURATION_MS > 0 && ACTIVE_MS > 0 && API_DURATION_MS > ACTIVE_MS )); then
  RATIO_X10=$(( API_DURATION_MS * 10 / ACTIVE_MS ))
  if (( RATIO_X10 >= 12 )); then
    RATIO_INT=$(( RATIO_X10 / 10 ))
    RATIO_DEC=$(( RATIO_X10 % 10 ))
    SPEEDUP_FMT=" [${RATIO_INT}.${RATIO_DEC}×]"
  fi
fi

# ============================================================
# 5. Cache Hit Rate (from current_usage, per-request snapshot)
# Formula: cache_read / (input + cache_read + cache_creation) × 100
# Hidden entirely when current_usage is null or denominator is 0
# ============================================================
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
CURRENT_INPUT=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')

# Handle null strings
[[ "$CACHE_READ" == "null" ]] && CACHE_READ=0
[[ "$CACHE_CREATE" == "null" ]] && CACHE_CREATE=0
[[ "$CURRENT_INPUT" == "null" ]] && CURRENT_INPUT=0

CACHE_TOTAL=$((CURRENT_INPUT + CACHE_READ + CACHE_CREATE))

CACHE_FMT=""
if (( CACHE_TOTAL > 0 )); then
  CACHE_HIT=$((CACHE_READ * 100 / CACHE_TOTAL))
  CACHE_FMT="Cached ${CACHE_HIT}% · "
fi

# ============================================================
# 5b. Rate Limits (subscribers only, displayed as Line 3)
# Format: Limits: 5h ▮▮▮▯▯▯▯▯▯▯ N% · 7d ▮▮▮▮▯▯▯▯▯▯ N% | ↻ Xh Ym · Xd Xh
# ============================================================
RATE_LINE=""

# Extract rate limit data in a single jq call
RATE_DATA=$(echo "$input" | jq -r '[
  .rate_limits.five_hour.used_percentage // "",
  .rate_limits.five_hour.resets_at // "",
  .rate_limits.seven_day.used_percentage // "",
  .rate_limits.seven_day.resets_at // ""
] | join("|")')
IFS='|' read -r R5_PCT R5_RESET R7_PCT R7_RESET <<< "$RATE_DATA"

# Only proceed if at least one window has data
if [[ -n "$R5_PCT" && "$R5_PCT" != "null" ]] || [[ -n "$R7_PCT" && "$R7_PCT" != "null" ]]; then

  # --- Gauge rendering function (10 chars, ▮▯) ---
  _rate_gauge() {
    local pct_int=$1
    local filled=$((pct_int * 10 / 100))
    (( filled > 10 )) && filled=10
    (( filled < 0 )) && filled=0
    local empty=$((10 - filled))
    local bar=""
    [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '▮')
    [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '▯')"
    echo "$bar"
  }

  # --- Countdown formatting function ---
  _rate_countdown() {
    local reset_epoch=$1
    if [[ -z "$reset_epoch" || "$reset_epoch" == "null" || "$reset_epoch" == "" ]]; then
      return 1  # No data
    fi
    local now
    now=$(date +%s)
    local diff=$(( reset_epoch - now ))
    if (( diff <= 0 )); then
      echo "<1m"
      return 0
    fi
    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))
    if (( days > 0 && hours > 0 )); then
      echo "${days}d ${hours}h"
    elif (( days > 0 )); then
      echo "${days}d"
    elif (( hours > 0 && mins > 0 )); then
      echo "${hours}h ${mins}m"
    elif (( hours > 0 )); then
      echo "${hours}h"
    elif (( mins > 0 )); then
      echo "${mins}m"
    else
      echo "<1m"
    fi
    return 0
  }

  # --- Build usage section ---
  RATE_USAGE=""
  R5_HAS_RESET=false R7_HAS_RESET=false
  R5_COUNTDOWN="" R7_COUNTDOWN=""

  if [[ -n "$R5_PCT" && "$R5_PCT" != "null" ]]; then
    R5_INT=$(printf "%.0f" "$R5_PCT")
    (( R5_INT < 0 )) && R5_INT=0
    (( R5_INT > 100 )) && R5_INT=100
    R5_BAR=$(_rate_gauge $R5_INT)
    RATE_USAGE="5h ${R5_BAR} ${R5_INT}%"
    if R5_COUNTDOWN=$(_rate_countdown "$R5_RESET"); then
      R5_HAS_RESET=true
    fi
  fi

  if [[ -n "$R7_PCT" && "$R7_PCT" != "null" ]]; then
    R7_INT=$(printf "%.0f" "$R7_PCT")
    (( R7_INT < 0 )) && R7_INT=0
    (( R7_INT > 100 )) && R7_INT=100
    R7_BAR=$(_rate_gauge $R7_INT)
    [[ -n "$RATE_USAGE" ]] && RATE_USAGE="$RATE_USAGE · "
    RATE_USAGE="${RATE_USAGE}7d ${R7_BAR} ${R7_INT}%"
    if R7_COUNTDOWN=$(_rate_countdown "$R7_RESET"); then
      R7_HAS_RESET=true
    fi
  fi

  # --- Build reset section ---
  RATE_RESET=""
  BOTH_BARS=$([[ -n "$R5_PCT" && "$R5_PCT" != "null" && -n "$R7_PCT" && "$R7_PCT" != "null" ]] && echo true || echo false)

  if $R5_HAS_RESET && $R7_HAS_RESET; then
    # Both countdowns: no labels, order matches bars
    RATE_RESET="↻ ${R5_COUNTDOWN} · ${R7_COUNTDOWN}"
  elif $R5_HAS_RESET && ! $R7_HAS_RESET; then
    if $BOTH_BARS; then
      # Ambiguous: add label
      RATE_RESET="↻ 5h: ${R5_COUNTDOWN}"
    else
      RATE_RESET="↻ ${R5_COUNTDOWN}"
    fi
  elif ! $R5_HAS_RESET && $R7_HAS_RESET; then
    if $BOTH_BARS; then
      RATE_RESET="↻ 7d: ${R7_COUNTDOWN}"
    else
      RATE_RESET="↻ ${R7_COUNTDOWN}"
    fi
  fi

  # --- Assemble RATE_LINE ---
  if [[ -n "$RATE_RESET" ]]; then
    RATE_LINE="Limits: ${RATE_USAGE} | ${RATE_RESET}"
  else
    RATE_LINE="Limits: ${RATE_USAGE}"
  fi
fi

# Output function for rate limits (called at every exit point)
_output_rate_limits() {
  if [[ -n "$RATE_LINE" ]]; then
    echo "───"
    echo "$RATE_LINE"
  fi
}

# ============================================================
# 6. Combine Output
# ============================================================
# Format: 49.7M tokens · $29.46 | Context: [bar] XX% | Cached XX% · ⏱ Xm ⏩N.N
# Token+Cost first, Context bar in middle (visual focus), Cache+Duration+Speedup last
# Always use full "Cached" label (no compression)
echo "$TOKENS_FMT tokens · $COST_FMT | $CONTEXT_BAR | $CACHE_FMT$DURATION_FMT$SPEEDUP_FMT"

# ============================================================
# 7. Dev Line 2 - Git Development Info (additive only)
# Trigger: git repo detected → output "───" separator + dev info line
# No git → nothing extra, Line 1 remains unchanged
# Format: branch [· N active] | +add -del · N files · N lines/$ | Quality: sparkline arrow
# ============================================================

# Extract dev fields in a single jq call
DEV_DATA=$(echo "$input" | jq -r '[
  .workspace.project_dir // "",
  .session_id // "",
  .cost.total_lines_added // "0",
  .cost.total_lines_removed // "0"
] | @tsv')
IFS=$'\t' read -r PROJECT_DIR SESSION_ID LINES_ADDED LINES_REMOVED <<< "$DEV_DATA"

# Handle null/empty values
[[ -z "$LINES_ADDED" || "$LINES_ADDED" == "null" ]] && LINES_ADDED=0
[[ -z "$LINES_REMOVED" || "$LINES_REMOVED" == "null" ]] && LINES_REMOVED=0
[[ -z "$SESSION_ID" ]] && SESSION_ID="default"
[[ -z "$PROJECT_DIR" ]] && { _output_rate_limits; exit 0; }

# Git detection: not a git repo → no Line 2, exit cleanly
git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null || { _output_rate_limits; exit 0; }

# Branch name (required for Line 2)
BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null)
[[ -z "$BRANCH" ]] && { _output_rate_limits; exit 0; }

# --- Data collection ---

# Collaboration: count Claude Code processes on same project
COLLAB_COUNT=$(pgrep -af "claude" 2>/dev/null | grep -cF "$PROJECT_DIR") || COLLAB_COUNT=0

# Diff statistics (single awk pass)
D_FILES=0 D_ADD=0 D_DEL=0
DIFF_RAW=$(git -C "$PROJECT_DIR" diff --numstat HEAD 2>/dev/null)
if [[ -n "$DIFF_RAW" ]]; then
  read -r D_FILES D_ADD D_DEL <<< "$(echo "$DIFF_RAW" | awk '{fc++; a+=$1; d+=$2} END {print fc, a+0, d+0}')"
fi

# Cost efficiency: lines per dollar (pure bash, no bc)
# Reuses $COST from Section 3 above
EFFICIENCY=""
TOTAL_LINES=$(( LINES_ADDED + LINES_REMOVED ))
if (( TOTAL_LINES > 0 )); then
  COST_INT="${COST%%.*}"
  COST_DEC="${COST#*.}"
  [[ "$COST_DEC" == "$COST" ]] && COST_DEC="00"
  [[ ${#COST_DEC} -eq 1 ]] && COST_DEC="${COST_DEC}0"
  [[ ${#COST_DEC} -gt 2 ]] && COST_DEC="${COST_DEC:0:2}"
  [[ -z "$COST_INT" ]] && COST_INT=0
  COST_CENTS=$(( 10#$COST_INT * 100 + 10#$COST_DEC ))
  if (( COST_CENTS >= 50 )); then
    EFF_VAL=$(( TOTAL_LINES * 100 / COST_CENTS ))
    EFFICIENCY="${EFF_VAL} lines/\$"
  fi
fi

# Sparkline: track change velocity over recent invocations
SPARKLINE=""
TREND_ARROW=""
SPARK_FILE="/tmp/statusline-spark-${SESSION_ID}"
CURRENT_TOTAL=$TOTAL_LINES

if [[ -f "$SPARK_FILE" ]]; then
  PREV_TOTAL=$(sed -n '1p' "$SPARK_FILE")
  PREV_DELTAS=$(sed -n '2p' "$SPARK_FILE")
  [[ -z "$PREV_TOTAL" ]] && PREV_TOTAL=0

  DELTA=$(( CURRENT_TOTAL - PREV_TOTAL ))
  (( DELTA < 0 )) && DELTA=0

  if [[ -n "$PREV_DELTAS" ]]; then
    DELTAS="${PREV_DELTAS},${DELTA}"
  else
    DELTAS="${DELTA}"
  fi
  DELTAS=$(echo "$DELTAS" | tr ',' '\n' | tail -8 | paste -sd ',' -)
else
  DELTAS=""
  DELTA=0
fi

printf '%s\n%s\n' "$CURRENT_TOTAL" "$DELTAS" > "$SPARK_FILE" 2>/dev/null

# Generate sparkline — always shown, 8 chars wide with "Quality:" prefix
# 0 data points: ▁▁▁▁▁▁▁▁ (empty state)
# 1-2 points: pad left with ▁, no trend arrow
# 3+ points: pad left with ▁, trend arrow appears
SPARK_CHARS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
SPARKLINE=""
TREND_ARROW=""

if [[ -n "$DELTAS" ]]; then
  IFS=',' read -ra SPARK_ARR <<< "$DELTAS"
  POINT_COUNT=${#SPARK_ARR[@]}
else
  SPARK_ARR=()
  POINT_COUNT=0
fi

if (( POINT_COUNT == 0 )); then
  SPARKLINE="▁▁▁▁▁▁▁▁"
else
  # Zero-separate + Log2 min-max normalization
  # - All-zero data → all ▁ (same as POINT_COUNT==0)
  # - Zero values → fixed IDX=1 (▂, area-chart baseline)
  # - Non-zero values → log2 then min-max normalize to IDX 2-7 (▃~█)
  # - Fallback to absolute scale when all non-zero values share same log2

  # Check if all values are zero
  MAX_VAL=0
  for v in "${SPARK_ARR[@]}"; do
    (( v > MAX_VAL )) && MAX_VAL=$v
  done

  if (( MAX_VAL == 0 )); then
    SPARKLINE="▁▁▁▁▁▁▁▁"
  else

  # Compute integer log2 for non-zero values
  MIN_LOG=999; MAX_LOG=0
  declare -a LOG_VALS=()
  for v in "${SPARK_ARR[@]}"; do
    if (( v > 0 )); then
      lv=0; tmp=$v
      while (( tmp > 1 )); do (( tmp >>= 1 )); (( lv++ )); done
      LOG_VALS+=($lv)
      (( lv < MIN_LOG )) && MIN_LOG=$lv
      (( lv > MAX_LOG )) && MAX_LOG=$lv
    else
      LOG_VALS+=(-1)  # sentinel for zero values
    fi
  done
  LOG_RANGE=$(( MAX_LOG - MIN_LOG ))

  # Build sparkline: always 8 chars, pad left with ▁
  PAD_COUNT=$(( 8 - POINT_COUNT ))
  (( PAD_COUNT < 0 )) && PAD_COUNT=0
  for (( i=0; i<PAD_COUNT; i++ )); do
    SPARKLINE="${SPARKLINE}▁"
  done
  for (( j=0; j<POINT_COUNT; j++ )); do
    v=${SPARK_ARR[$j]}
    if (( v == 0 )); then
      IDX=1  # ▂ — area-chart baseline for zero activity
    elif (( LOG_RANGE == 0 )); then
      # All non-zero values share same log2 → absolute scale (IDX 2-7)
      if   (( v <= 5 ));   then IDX=2
      elif (( v <= 15 ));  then IDX=3
      elif (( v <= 40 ));  then IDX=4
      elif (( v <= 100 )); then IDX=5
      elif (( v <= 250 )); then IDX=6
      else IDX=7; fi
    else
      # Log2 min-max normalization → IDX 2-7
      lv=${LOG_VALS[$j]}
      IDX=$(( (lv - MIN_LOG) * 5 / LOG_RANGE + 2 ))
      (( IDX > 7 )) && IDX=7
      (( IDX < 2 )) && IDX=2
    fi
    SPARKLINE="${SPARKLINE}${SPARK_CHARS[$IDX]}"
  done
  fi  # end MAX_VAL == 0

  # Trend arrow only with >= 3 data points
  if (( POINT_COUNT >= 3 )); then
    HALF=$(( POINT_COUNT / 2 ))
    SUM_FIRST=0; SUM_SECOND=0
    for (( i=0; i<HALF; i++ )); do
      SUM_FIRST=$(( SUM_FIRST + SPARK_ARR[i] ))
    done
    for (( i=HALF; i<POINT_COUNT; i++ )); do
      SUM_SECOND=$(( SUM_SECOND + SPARK_ARR[i] ))
    done
    AVG_FIRST=$(( SUM_FIRST * 100 / HALF ))
    AVG_SECOND=$(( SUM_SECOND * 100 / (POINT_COUNT - HALF) ))
    DIFF_PCT=0
    (( AVG_FIRST > 0 )) && DIFF_PCT=$(( (AVG_SECOND - AVG_FIRST) * 100 / AVG_FIRST ))
    if (( DIFF_PCT > 20 )); then
      TREND_ARROW=" ↑"
    elif (( DIFF_PCT < -20 )); then
      TREND_ARROW=" ↓"
    else
      TREND_ARROW=" →"
    fi
  fi
fi

# --- Assemble Line 2 ---
# Groups: [branch · N active] | [diff · files · efficiency] | [Quality: sparkline arrow]

GRP1="$BRANCH"
(( COLLAB_COUNT >= 2 )) && GRP1="$GRP1 · ${COLLAB_COUNT} active"

GRP2=""
if (( D_FILES > 0 )); then
  GRP2="+${D_ADD} -${D_DEL}"
  (( D_FILES == 1 )) && GRP2="$GRP2 · 1 file" || GRP2="$GRP2 · ${D_FILES} files"
  [[ -n "$EFFICIENCY" ]] && GRP2="$GRP2 · $EFFICIENCY"
else
  GRP2="clean"
fi

GRP3="Quality: ${SPARKLINE}${TREND_ARROW}"

LINE2="$GRP1 | $GRP2 | $GRP3"

echo "───"
echo "$LINE2"

_output_rate_limits
