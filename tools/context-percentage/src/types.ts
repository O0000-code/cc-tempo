/**
 * Type definitions for Claude Code Context Percentage
 * Based on CCometixLine's implementation
 */

// Claude Code Hook Data (stdin input)
export interface ClaudeHookData {
  session_id: string;
  transcript_path: string;
  model: {
    id: string;
    display_name: string;
  };
  workspace: {
    current_dir: string;
    project_dir: string;
  };
  cwd?: string;
  version?: string;
  cost?: {
    total_cost_usd?: number;
    total_duration_ms?: number;
  };
}

// Usage data from Claude API response
export interface Usage {
  input_tokens?: number;
  output_tokens?: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
  // OpenAI format compatibility
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  cached_tokens?: number;
}

// Message in transcript entry
export interface Message {
  id?: string;
  usage?: Usage;
  model?: string;
}

// Transcript JSONL entry
export interface TranscriptEntry {
  type?: "user" | "assistant" | "summary" | string;
  timestamp?: string;
  message?: Message;
  uuid?: string;
  parentUuid?: string;
  leafUuid?: string;  // Only in summary type
  summary?: string;
}

// Normalized usage after processing
export interface NormalizedUsage {
  inputTokens: number;
  outputTokens: number;
  cacheCreationInputTokens: number;
  cacheReadInputTokens: number;
}

// Model configuration entry
export interface ModelEntry {
  pattern: string;
  displayName: string;
  contextLimit: number;
}
