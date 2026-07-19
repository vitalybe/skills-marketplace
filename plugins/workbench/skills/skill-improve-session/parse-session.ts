#!/usr/bin/env node

import { readFileSync } from "fs";
import { homedir } from "os";
import path from "path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface SessionEntry {
  type: string;
  message?: {
    role?: string;
    content?: string | ContentBlock[];
  };
  isSidechain?: boolean;
  timestamp?: string;
  uuid?: string;
  toolUseResult?: unknown;
  data?: {
    type?: string;
  };
}

interface ContentBlock {
  type: string;
  text?: string;
  thinking?: string;
  name?: string;
  input?: Record<string, unknown>;
  tool_use_id?: string;
  content?: string | ContentBlock[];
  is_error?: boolean;
  isMeta?: boolean;
}

function truncate(s: string, maxLen: number): string {
  if (s.length <= maxLen) return s;
  return s.slice(0, maxLen) + "…";
}

function stripSystemReminders(text: string): string {
  return text.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, "").trim();
}

function extractTextFromContent(content: string | ContentBlock[]): string {
  if (typeof content === "string") return content;
  return content
    .filter((b) => b.type === "text" && b.text)
    .map((b) => b.text!)
    .join("\n");
}

function formatToolCall(block: ContentBlock): string {
  const name = block.name ?? "unknown";
  const input = block.input ?? {};

  // Format key params, truncated
  const params = Object.entries(input)
    .filter(([, v]) => v !== undefined && v !== null)
    .map(([k, v]) => {
      const val = typeof v === "string" ? v : JSON.stringify(v);
      return `${k}=${truncate(val, 200)}`;
    })
    .join(", ");

  return `**Tool: ${name}** — ${truncate(params, 400)}`;
}

function formatToolResult(content: string | ContentBlock[]): string {
  if (typeof content === "string") {
    const cleaned = stripSystemReminders(content);
    return cleaned ? truncate(cleaned, 300) : "(empty)";
  }
  if (Array.isArray(content)) {
    return content
      .map((b) => {
        if (b.type === "tool_result") {
          const resultText = typeof b.content === "string" ? b.content : JSON.stringify(b.content);
          const prefix = b.is_error ? "**ERROR:** " : "";
          return prefix + truncate(stripSystemReminders(resultText), 300);
        }
        if (b.type === "text" && b.text) {
          return truncate(stripSystemReminders(b.text), 300);
        }
        return null;
      })
      .filter(Boolean)
      .join("\n");
  }
  return "(unknown format)";
}

function parseSession(sessionPath: string): string {
  const raw = readFileSync(sessionPath, "utf-8");
  const lines = raw.split("\n").filter((l) => l.trim());

  const entries: SessionEntry[] = [];
  for (const line of lines) {
    try {
      entries.push(JSON.parse(line));
    } catch {
      // Skip unparseable lines
    }
  }

  const output: string[] = [];
  output.push(`# Session Transcript`);
  output.push(`**File:** ${sessionPath}`);
  output.push(`**Entries:** ${entries.length}`);
  output.push("");

  for (const entry of entries) {
    // Skip sidechains, progress, file snapshots
    if (entry.isSidechain) continue;
    if (entry.type === "progress") continue;
    if (entry.type === "file-history-snapshot") continue;
    if (entry.type === "queue-operation") continue;

    const role = entry.message?.role;
    const content = entry.message?.content;
    if (!content) continue;

    if (entry.type === "user" && role === "user") {
      // Check if it's a tool result
      if (Array.isArray(content)) {
        const toolResults = content.filter((b: ContentBlock) => b.type === "tool_result");
        if (toolResults.length > 0) {
          for (const tr of toolResults) {
            const isError = tr.is_error;
            const resultText = typeof tr.content === "string" ? tr.content : JSON.stringify(tr.content);
            const cleaned = stripSystemReminders(resultText);
            if (!cleaned) continue;
            const prefix = isError ? "### Tool Result (ERROR)" : "### Tool Result";
            output.push(prefix);
            output.push(truncate(cleaned, 500));
            output.push("");
          }
          continue;
        }
        // Check for isMeta (skill injection)
        const metaBlocks = content.filter((b: ContentBlock) => b.isMeta);
        if (metaBlocks.length > 0) {
          output.push("### Skill Injection");
          for (const mb of metaBlocks) {
            const text = mb.text ?? "";
            output.push(truncate(stripSystemReminders(text), 300));
          }
          output.push("");
          continue;
        }
      }

      // Regular user message
      const text = extractTextFromContent(content);
      const cleaned = stripSystemReminders(text);
      if (!cleaned) continue;
      output.push("## User");
      output.push(cleaned);
      output.push("");
    } else if (entry.type === "assistant" && role === "assistant") {
      if (!Array.isArray(content)) {
        const cleaned = stripSystemReminders(content);
        if (cleaned) {
          output.push("## Assistant");
          output.push(cleaned);
          output.push("");
        }
        continue;
      }

      const parts: string[] = [];
      for (const block of content as ContentBlock[]) {
        if (block.type === "text" && block.text) {
          const cleaned = stripSystemReminders(block.text);
          if (cleaned) parts.push(cleaned);
        } else if (block.type === "tool_use") {
          parts.push(formatToolCall(block));
        }
        // Skip thinking blocks
      }

      if (parts.length > 0) {
        output.push("## Assistant");
        output.push(parts.join("\n\n"));
        output.push("");
      }
    } else if (entry.type === "system") {
      // System messages - brief note
      const text = extractTextFromContent(content);
      const cleaned = stripSystemReminders(text);
      if (cleaned) {
        output.push("### System");
        output.push(truncate(cleaned, 200));
        output.push("");
      }
    }
  }

  return output.join("\n");
}

async function main(): Promise<void> {
  const argv = await yargs(hideBin(process.argv))
    .option("session", {
      alias: "s",
      type: "string",
      description: "Session ID (UUID)",
      demandOption: true,
    })
    .help()
    .alias("help", "h")
    .parseAsync();

  const sessionId = argv.session;
  const projectsRoot = path.join(homedir(), ".claude/projects");
  const fileName = `${sessionId}.jsonl`;

  // Search all project directories for the session file
  let sessionPath: string | null = null;
  const { readdirSync, statSync } = await import("fs");
  for (const dir of readdirSync(projectsRoot)) {
    const candidate = path.join(projectsRoot, dir, fileName);
    try {
      statSync(candidate);
      sessionPath = candidate;
      break;
    } catch {
      // not in this dir
    }
  }

  if (!sessionPath) {
    console.error(`Session file not found in any project directory: ${fileName}`);
    process.exit(1);
  }

  const result = parseSession(sessionPath);
  console.log(result);
}

main().catch((error) => {
  console.error("Failed:", error.message);
  process.exit(1);
});
