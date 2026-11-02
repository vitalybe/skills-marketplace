---
name: requirements
description: Turn a feature idea into a short, simple, product-facing requirements doc with only the minimal critical technical details. Use whenever the user asks to "write requirements", "spec this", "what are the requirements for X", "requirements for this feature", or wants a plain-language summary of what to build before any planning or code. Explores the codebase first when details are needed, asks the user instead of listing open questions.
---

# Requirements

Produce a short requirements doc a product person can read in a minute. Output requirements only: no plan, no code, no file edits.

## Steps

1. **Understand the idea.** Restate the goal in one sentence to yourself.
2. **Explore if needed.** Check the codebase for what already exists (similar features, auth, config, docs) so the requirements fit reality. Do not guess facts you can look up. Do not explore what you do not need.
3. **Ask, do not list.** If something is unclear and it changes the requirements, ask the user (AskUserQuestion) before writing. Never put an "open questions" section in the doc.
4. **Write the doc** in the shape below and print it in the reply.

## Shape

Use only the sections that apply, in this order:

- **What it does** - 1 to 3 sentences, the outcome for the user.
- **How it works** - a short numbered list of the flow, in plain words.
- **What you see** - the user experience: commands, screens, messages, confirmations, failures.
- **Options** - flags or settings, one line each. Skip if none.
- **Safety** - what is protected: backups, access, read-only, all-or-nothing.
- **Not included** - what is deliberately out of scope.

## Rules

- Product facing and plain language. A reader who has not seen the code should follow it.
- Keep technical detail minimal and critical only: a URL, a command name, an env var or secret name, a path. No code, no function names, no schemas unless they are the requirement.
- Short. Bullets over paragraphs. Cut anything that does not change what gets built.
- No open questions, no TODOs, no "TBD". Decide, or ask the user first.
- Describe the current decision only. Do not narrate edits or alternatives you dropped.
- No em dashes. Use short dashes.
