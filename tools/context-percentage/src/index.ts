#!/usr/bin/env node

/**
 * Claude Context Percentage - StatusLine Command
 *
 * Usage:
 *   Add to ~/.claude/settings.json:
 *   {
 *     "statusLine": {
 *       "type": "command",
 *       "command": "claude-context-percentage"
 *     }
 *   }
 *
 * Options:
 *   --simple    Output simple percentage (e.g., "65%")
 *   --bar       Output progress bar (default, e.g., "Context: ████████████░░░░░░░░ 65%")
 *
 * Algorithm based on CCometixLine's context_window.rs
 */

import { json } from "stream/consumers";
import {
  getContextPercentageDisplay,
  getContextProgressBarDisplay,
  getTotalSessionTokensDisplay,
} from "./calculator";
import type { ClaudeHookData } from "./types";

// Parse command line arguments
function parseArgs(): { simple: boolean; tokens: boolean } {
  const args = process.argv.slice(2);
  return {
    simple: args.includes("--simple"),
    tokens: args.includes("--tokens"),
  };
}

async function main(): Promise<void> {
  try {
    const { simple, tokens } = parseArgs();

    // Check if running interactively (no stdin)
    if (process.stdin.isTTY) {
      console.error(`claude-context-percentage - Context percentage for Claude Code

Usage: This tool is designed to be used as a Claude Code statusLine command.

Options:
  --simple    Output simple percentage (e.g., "65%")
  --bar       Output progress bar (default)
  --tokens    Output total session tokens (e.g., "2.2M")

Add to ~/.claude/settings.json:
{
  "statusLine": {
    "type": "command",
    "command": "claude-context-percentage"
  }
}

Output format (default progress bar):
  Context: ████████████░░░░░░░░ 65%

Output format (--simple):
  65%

Output format (--tokens):
  2.2M

To test manually:
echo '{"transcript_path":"/path/to/session.jsonl","model":{"id":"claude-sonnet-4-5"}}' | claude-context-percentage`);
      process.exit(1);
    }

    // Read hook data from stdin
    const hookData = (await json(process.stdin)) as ClaudeHookData;

    if (!hookData) {
      console.error("Error: No input data received from stdin");
      process.exit(1);
    }

    const transcriptPath = hookData.transcript_path;
    const modelId = hookData.model?.id || "claude-sonnet-4-5";

    if (!transcriptPath) {
      // No transcript path, output placeholder
      console.log("-");
      return;
    }

    // Output based on mode
    if (tokens) {
      // Token mode: output total session tokens
      const tokenDisplay = getTotalSessionTokensDisplay(transcriptPath);
      console.log(tokenDisplay);
    } else if (simple) {
      // Simple mode: output percentage only
      const percentage = getContextPercentageDisplay(transcriptPath, modelId);
      console.log(percentage);
    } else {
      // Default mode: output progress bar
      const progressBar = getContextProgressBarDisplay(transcriptPath, modelId);
      console.log(progressBar);
    }
  } catch (error) {
    // Graceful error handling - output placeholder instead of crashing
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error("Error:", errorMessage);
    console.log("-");
    process.exit(1);
  }
}

main();
