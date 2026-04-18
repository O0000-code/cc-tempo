/**
 * Model configuration for context limits
 * Based on CCometixLine's models.rs
 */

import type { ModelEntry } from "./types";

// Default model configurations
const MODEL_ENTRIES: ModelEntry[] = [
  // 1M context models (put first for priority matching)
  {
    pattern: "[1m]",
    displayName: "Sonnet 4.5 1M",
    contextLimit: 1_000_000,
  },
  // Standard Claude models
  {
    pattern: "claude-3-7-sonnet",
    displayName: "Sonnet 3.7",
    contextLimit: 200_000,
  },
  // Third-party models
  {
    pattern: "glm-4.5",
    displayName: "GLM-4.5",
    contextLimit: 128_000,
  },
  {
    pattern: "kimi-k2-turbo",
    displayName: "Kimi K2 Turbo",
    contextLimit: 128_000,
  },
  {
    pattern: "kimi-k2",
    displayName: "Kimi K2",
    contextLimit: 128_000,
  },
  {
    pattern: "qwen3-coder",
    displayName: "Qwen Coder",
    contextLimit: 256_000,
  },
];

// Default context limit
const DEFAULT_CONTEXT_LIMIT = 200_000;

/**
 * Get context limit for a model based on ID pattern matching
 * @param modelId - The model ID from Claude Code
 * @returns Context limit in tokens
 */
export function getContextLimit(modelId: string): number {
  const modelLower = modelId.toLowerCase();

  for (const entry of MODEL_ENTRIES) {
    if (modelLower.includes(entry.pattern.toLowerCase())) {
      return entry.contextLimit;
    }
  }

  return DEFAULT_CONTEXT_LIMIT;
}

/**
 * Get display name for a model (optional utility)
 * @param modelId - The model ID from Claude Code
 * @returns Display name or undefined if no match
 */
export function getDisplayName(modelId: string): string | undefined {
  const modelLower = modelId.toLowerCase();

  for (const entry of MODEL_ENTRIES) {
    if (modelLower.includes(entry.pattern.toLowerCase())) {
      return entry.displayName;
    }
  }

  return undefined;
}
