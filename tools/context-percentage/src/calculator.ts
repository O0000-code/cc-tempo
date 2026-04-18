/**
 * Context percentage calculator
 * Based on CCometixLine's algorithm
 */

import { parseTranscriptUsage, parseTranscriptTotalTokens } from "./parser";
import type { TokenBreakdown } from "./parser";
import { getContextLimit } from "./models";

export type { TokenBreakdown };

export interface ContextInfo {
  percentage: number;
  tokens: number;
  limit: number;
  formatted: string;
}

// Progress bar configuration (matching Claude official style)
const PROGRESS_BAR_LENGTH = 20;
const FILLED_CHAR = "█";  // U+2588 FULL BLOCK
const EMPTY_CHAR = "░";   // U+2591 LIGHT SHADE

/**
 * Format percentage for display
 * - Integer if no decimal part
 * - One decimal place otherwise
 */
function formatPercentage(percentage: number): string {
  if (percentage === Math.floor(percentage)) {
    return `${Math.floor(percentage)}%`;
  }
  return `${percentage.toFixed(1)}%`;
}

/**
 * Format token count for display
 * - K for thousands
 * - M for millions
 */
function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000) {
    const mValue = tokens / 1_000_000;
    return mValue === Math.floor(mValue)
      ? `${Math.floor(mValue)}M`
      : `${mValue.toFixed(1)}M`;
  } else if (tokens >= 1_000) {
    const kValue = tokens / 1_000;
    return kValue === Math.floor(kValue)
      ? `${Math.floor(kValue)}k`
      : `${kValue.toFixed(1)}k`;
  }
  return tokens.toString();
}

/**
 * Calculate context percentage
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @param modelId - The model ID for determining context limit
 * @returns Context info or null if no data available
 */
export function calculateContextPercentage(
  transcriptPath: string,
  modelId: string
): ContextInfo | null {
  // 1. Get context limit based on model
  const contextLimit = getContextLimit(modelId);

  // 2. Parse transcript to get context tokens
  const contextTokens = parseTranscriptUsage(transcriptPath);

  if (contextTokens === null) {
    return null;
  }

  // 3. Calculate percentage
  const percentage = (contextTokens / contextLimit) * 100;

  // 4. Format output
  const formatted = formatPercentage(percentage);

  return {
    percentage,
    tokens: contextTokens,
    limit: contextLimit,
    formatted,
  };
}

/**
 * Get formatted context percentage string
 * This is the main function for StatusLine output
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @param modelId - The model ID for determining context limit
 * @returns Formatted percentage string or "-" if no data
 */
export function getContextPercentageDisplay(
  transcriptPath: string,
  modelId: string
): string {
  const info = calculateContextPercentage(transcriptPath, modelId);
  return info ? info.formatted : "-";
}

/**
 * Get detailed context information for debugging
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @param modelId - The model ID for determining context limit
 * @returns Detailed string or "-" if no data
 */
export function getContextDetailedDisplay(
  transcriptPath: string,
  modelId: string
): string {
  const info = calculateContextPercentage(transcriptPath, modelId);
  if (!info) {
    return "-";
  }

  const tokensStr = formatTokens(info.tokens);
  return `${info.formatted} (${tokensStr}/${formatTokens(info.limit)})`;
}

/**
 * Render progress bar with filled and empty blocks
 * Matches Claude official StatusLine style
 *
 * @param percentage - The percentage value (0-100)
 * @returns Progress bar string like "████████████░░░░░░░░"
 */
function renderProgressBar(percentage: number): string {
  // Clamp percentage to 0-100
  const clampedPercentage = Math.max(0, Math.min(100, percentage));

  // Calculate filled count (round to nearest integer)
  const filledCount = Math.round((clampedPercentage / 100) * PROGRESS_BAR_LENGTH);
  const emptyCount = PROGRESS_BAR_LENGTH - filledCount;

  // Build progress bar
  return FILLED_CHAR.repeat(filledCount) + EMPTY_CHAR.repeat(emptyCount);
}

/**
 * Get context display with progress bar (Claude official style)
 * Format: "Context: ████████████░░░░░░░░ XX%"
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @param modelId - The model ID for determining context limit
 * @returns Progress bar string or "Context: - " if no data
 */
export function getContextProgressBarDisplay(
  transcriptPath: string,
  modelId: string
): string {
  const info = calculateContextPercentage(transcriptPath, modelId);

  if (!info) {
    return `Context: ${EMPTY_CHAR.repeat(PROGRESS_BAR_LENGTH)} -`;
  }

  const progressBar = renderProgressBar(info.percentage);
  const percentageStr = Math.round(info.percentage);

  return `Context: ${progressBar} ${percentageStr}%`;
}

/**
 * Get total session tokens (sum of all messages in the session)
 * Includes: input + output + cache_creation + cache_read
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @returns Token breakdown or null if no data
 */
export function getTotalSessionTokens(
  transcriptPath: string
): TokenBreakdown | null {
  return parseTranscriptTotalTokens(transcriptPath);
}

/**
 * Get formatted total session tokens display
 * Format: "2.2M" or "125K" or "500"
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @returns Formatted token string or "-" if no data
 */
export function getTotalSessionTokensDisplay(
  transcriptPath: string
): string {
  const breakdown = parseTranscriptTotalTokens(transcriptPath);

  if (!breakdown) {
    return "-";
  }

  return formatTokens(breakdown.totalTokens);
}
