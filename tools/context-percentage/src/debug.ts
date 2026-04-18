#!/usr/bin/env node

/**
 * Debug version - shows detailed calculation
 */

import { existsSync, readFileSync } from "fs";
import { parseTranscriptUsage, normalizeUsage, calculateContextTokens } from "./parser";
import { getContextLimit } from "./models";

interface TranscriptEntry {
  type?: string;
  message?: {
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };
}

function debugAnalysis(transcriptPath: string, modelId: string): void {
  console.log("=== Context Percentage Debug ===\n");
  console.log(`Transcript Path: ${transcriptPath}`);
  console.log(`Model ID: ${modelId}`);
  console.log(`File Exists: ${existsSync(transcriptPath)}`);

  // Get context limit
  const contextLimit = getContextLimit(modelId);
  console.log(`Context Limit: ${contextLimit.toLocaleString()}`);

  // Parse and show result
  const contextTokens = parseTranscriptUsage(transcriptPath);
  console.log(`\nContext Tokens: ${contextTokens?.toLocaleString() ?? "null"}`);

  if (contextTokens !== null) {
    const percentage = (contextTokens / contextLimit) * 100;
    console.log(`Percentage: ${percentage.toFixed(4)}%`);
    console.log(`Formatted: ${percentage.toFixed(1)}%`);
  }

  // Show last few assistant messages for verification
  console.log("\n=== Last Assistant Messages ===");
  if (existsSync(transcriptPath)) {
    const content = readFileSync(transcriptPath, "utf-8");
    const lines = content.split("\n").filter((l) => l.trim());

    let count = 0;
    for (let i = lines.length - 1; i >= 0 && count < 3; i--) {
      try {
        const entry = JSON.parse(lines[i]) as TranscriptEntry;
        if (entry.type === "assistant" && entry.message?.usage) {
          count++;
          const u = entry.message.usage;
          const normalized = normalizeUsage(u);
          const tokens = calculateContextTokens(normalized);
          console.log(`\n[${count}] Line ${i + 1}:`);
          console.log(`  input_tokens: ${u.input_tokens ?? 0}`);
          console.log(`  cache_creation_input_tokens: ${u.cache_creation_input_tokens ?? 0}`);
          console.log(`  cache_read_input_tokens: ${u.cache_read_input_tokens ?? 0}`);
          console.log(`  output_tokens: ${u.output_tokens ?? 0}`);
          console.log(`  => context_tokens: ${tokens}`);
          console.log(`  => percentage: ${((tokens / contextLimit) * 100).toFixed(2)}%`);
        }
      } catch {
        // Skip invalid lines
      }
    }
  }
}

// Run debug
const transcriptPath = process.argv[2];
const modelId = process.argv[3] || "claude-sonnet-4-5";

if (!transcriptPath) {
  console.error("Usage: debug <transcript_path> [model_id]");
  console.error("  model_id defaults to 'claude-sonnet-4-5' (200k context)");
  process.exit(1);
}

debugAnalysis(transcriptPath, modelId);
