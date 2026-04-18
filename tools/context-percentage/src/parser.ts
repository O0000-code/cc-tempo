/**
 * Transcript JSONL parser
 * Based on CCometixLine's context_window.rs algorithm
 *
 * Key insight: We only need the LAST assistant message's usage,
 * NOT the sum of all usages. This is because Claude API's input_tokens
 * already includes the full context (system prompt + history + current message).
 */

import { readFileSync, existsSync, readdirSync, statSync } from "fs";
import { dirname, join } from "path";
import type { TranscriptEntry, Usage, NormalizedUsage } from "./types";

/**
 * Normalize usage data from different LLM providers
 * Handles both Anthropic and OpenAI formats
 */
export function normalizeUsage(usage: Usage): NormalizedUsage {
  return {
    // Priority: Anthropic format > OpenAI format
    inputTokens: usage.input_tokens ?? usage.prompt_tokens ?? 0,
    outputTokens: usage.output_tokens ?? usage.completion_tokens ?? 0,
    cacheCreationInputTokens: usage.cache_creation_input_tokens ?? 0,
    cacheReadInputTokens: usage.cache_read_input_tokens ?? usage.cached_tokens ?? 0,
  };
}

/**
 * Calculate context tokens from normalized usage
 * Formula: input + cache_creation + cache_read + output
 */
export function calculateContextTokens(usage: NormalizedUsage): number {
  return (
    usage.inputTokens +
    usage.cacheCreationInputTokens +
    usage.cacheReadInputTokens +
    usage.outputTokens
  );
}

/**
 * Parse a single JSONL line
 */
function parseLine(line: string): TranscriptEntry | null {
  const trimmed = line.trim();
  if (!trimmed) return null;

  try {
    return JSON.parse(trimmed) as TranscriptEntry;
  } catch {
    return null;
  }
}

/**
 * Read all lines from a JSONL file
 */
function readJsonlLines(filePath: string): string[] {
  if (!existsSync(filePath)) {
    return [];
  }

  try {
    const content = readFileSync(filePath, "utf-8");
    return content.split("\n").filter((line) => line.trim());
  } catch {
    return [];
  }
}

/**
 * Find assistant message by UUID in file
 */
function findAssistantMessageByUuid(
  lines: string[],
  targetUuid: string
): number | null {
  for (const line of lines) {
    const entry = parseLine(line);
    if (
      entry &&
      entry.uuid === targetUuid &&
      entry.type === "assistant" &&
      entry.message?.usage
    ) {
      const normalized = normalizeUsage(entry.message.usage);
      return calculateContextTokens(normalized);
    }
  }
  return null;
}

/**
 * Search for usage by leafUuid across project files
 * This handles the summary case where we need to find the actual message
 */
function findUsageByLeafUuid(
  leafUuid: string,
  projectDir: string
): number | null {
  if (!existsSync(projectDir)) {
    return null;
  }

  try {
    const files = readdirSync(projectDir);
    const jsonlFiles = files.filter((f) => f.endsWith(".jsonl"));

    for (const file of jsonlFiles) {
      const filePath = join(projectDir, file);
      const lines = readJsonlLines(filePath);

      // Search for the target UUID
      for (const line of lines) {
        const entry = parseLine(line);
        if (!entry || entry.uuid !== leafUuid) continue;

        if (entry.type === "assistant" && entry.message?.usage) {
          // Direct assistant message with usage
          const normalized = normalizeUsage(entry.message.usage);
          return calculateContextTokens(normalized);
        } else if (entry.type === "user" && entry.parentUuid) {
          // User message, need to find parent assistant message
          return findAssistantMessageByUuid(lines, entry.parentUuid);
        }
      }
    }
  } catch {
    return null;
  }

  return null;
}

/**
 * Try to parse transcript file and get context tokens
 * Returns the context tokens from the LAST assistant message
 */
function tryParseTranscriptFile(filePath: string): number | null {
  const lines = readJsonlLines(filePath);
  if (lines.length === 0) {
    return null;
  }

  // Check if the last line is a summary
  const lastLine = lines[lines.length - 1];
  const lastEntry = parseLine(lastLine);

  if (lastEntry?.type === "summary" && lastEntry.leafUuid) {
    // Handle summary case: find usage by leafUuid
    const projectDir = dirname(filePath);
    return findUsageByLeafUuid(lastEntry.leafUuid, projectDir);
  }

  // Normal case: find the last assistant message in current file
  // Iterate in reverse order (from end to beginning)
  for (let i = lines.length - 1; i >= 0; i--) {
    const entry = parseLine(lines[i]);

    if (entry?.type === "assistant" && entry.message?.usage) {
      const normalized = normalizeUsage(entry.message.usage);
      return calculateContextTokens(normalized);
    }
  }

  return null;
}

/**
 * Try to find usage from project history when transcript doesn't exist
 */
function tryFindUsageFromProjectHistory(
  transcriptPath: string
): number | null {
  const projectDir = dirname(transcriptPath);

  if (!existsSync(projectDir)) {
    return null;
  }

  try {
    const files = readdirSync(projectDir);
    const jsonlFiles = files.filter((f) => f.endsWith(".jsonl"));

    if (jsonlFiles.length === 0) {
      return null;
    }

    // Sort by modification time (most recent first)
    const filesWithMtime = jsonlFiles.map((f) => {
      const fullPath = join(projectDir, f);
      const stat = statSync(fullPath);
      return { path: fullPath, mtime: stat.mtime.getTime() };
    });
    filesWithMtime.sort((a, b) => b.mtime - a.mtime);

    // Try to find usage from the most recent session
    for (const { path } of filesWithMtime) {
      const usage = tryParseTranscriptFile(path);
      if (usage !== null) {
        return usage;
      }
    }
  } catch {
    return null;
  }

  return null;
}

/**
 * Parse transcript and get context tokens
 * Main entry point for getting usage data
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @returns Context tokens or null if not available
 */
export function parseTranscriptUsage(transcriptPath: string): number | null {
  // Try to parse from current transcript file
  if (existsSync(transcriptPath)) {
    const usage = tryParseTranscriptFile(transcriptPath);
    if (usage !== null) {
      return usage;
    }
  }

  // If file doesn't exist or no usage found, try project history
  return tryFindUsageFromProjectHistory(transcriptPath);
}

/**
 * Token breakdown for total session statistics
 */
export interface TokenBreakdown {
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
  totalTokens: number;
}

/**
 * Parse transcript and get TOTAL session tokens (sum of all messages)
 * This is different from parseTranscriptUsage which only gets the last message
 *
 * @param transcriptPath - Path to the transcript JSONL file
 * @returns Token breakdown with all token types, or null if not available
 */
export function parseTranscriptTotalTokens(
  transcriptPath: string
): TokenBreakdown | null {
  if (!existsSync(transcriptPath)) {
    return null;
  }

  const lines = readJsonlLines(transcriptPath);
  if (lines.length === 0) {
    return null;
  }

  let inputTokens = 0;
  let outputTokens = 0;
  let cacheCreationTokens = 0;
  let cacheReadTokens = 0;

  for (const line of lines) {
    const entry = parseLine(line);
    if (!entry || !entry.message?.usage) {
      continue;
    }

    const normalized = normalizeUsage(entry.message.usage);
    inputTokens += normalized.inputTokens;
    outputTokens += normalized.outputTokens;
    cacheCreationTokens += normalized.cacheCreationInputTokens;
    cacheReadTokens += normalized.cacheReadInputTokens;
  }

  const totalTokens =
    inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens;

  // Return null if no tokens found
  if (totalTokens === 0) {
    return null;
  }

  return {
    inputTokens,
    outputTokens,
    cacheCreationTokens,
    cacheReadTokens,
    totalTokens,
  };
}
