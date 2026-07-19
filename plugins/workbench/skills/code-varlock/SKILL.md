---
name: code-varlock
description: Set up, extend, or debug a `varlock` schema in a Node.js/TypeScript project - schema-driven env with validation, type generation, and 1Password secret resolution. Use this skill whenever the user asks to adopt varlock, migrate off dotenv, set up `.env.schema`, add a new var to an existing varlock schema, wire up the `@varlock/1password-plugin` (`op(...)` refs, `@initOp`), diagnose "Unknown resolver function" / "No 1Password plugin instances found" / varlock parse errors, or investigate why a varlock-loaded script exits silently. Also use when the user mentions "AI-safe .env", schema-first env, or wants to commit env shape without leaking secrets.
---

# Migrate dotenv → varlock

Varlock replaces `dotenv` with a schema-first env loader. The `.env.schema` file is committed (safe - shape only, no secrets), validates required values at startup, and can resolve secrets from 1Password at runtime via `op(...)` expressions.

This skill captures the exact steps and the landmines that aren't obvious from the docs. It assumes a Node.js/TypeScript project using ESM; for other integrations (Next.js, Vite, Astro, SvelteKit) see https://varlock.dev - the overall shape is the same, only the import line differs.

## Migration steps

### 1. Swap the dependency

```bash
pnpm remove dotenv && pnpm add varlock
# add the 1P plugin if any secret should come from 1Password:
pnpm add @varlock/1password-plugin
```

Use the project's package manager (npm / yarn / bun work the same). Peer-dep warnings about varlock version from plugins are usually safe to ignore as long as the installed varlock is newer than the peer range.

### 2. Swap the import at the entrypoint

Find the single `import "dotenv/config"` (or `require("dotenv").config()`) in the app entrypoint and replace it:

```ts
// before
import "dotenv/config";
// after
import "varlock/auto-load";
```

`process.env.*` reads continue to work unchanged throughout the codebase - no other code edits are needed for a minimal migration. If the user wants type-safe access with IntelliSense they can later switch to `import { ENV } from "varlock/env"`, but that's optional polish, not part of the migration.

### 3. Author `.env.schema`

Enumerate every env var the app reads (`rg 'process\.env\.' src/`) and describe each one in a schema file at the repo root. Structure:

```
# @defaultRequired=infer
# @defaultSensitive=true
# ---

# Short human description goes here as a regular comment.
# @required
# @sensitive=true
# @type=string
SOME_VAR=optional_default_value
```

Root decorators (above the `# ---` separator) set defaults for the whole file. Per-item decorators are comment lines **directly above** the variable - blank lines break the association.

Common item decorators:
- `@required` / `@optional` - override the file-level default
- `@sensitive=true` / `@sensitive=false` - controls log redaction; set `false` for non-secret config (chat IDs, paths, feature flags)
- `@type=string` / `@type=number` / `@type=enum(a,b,c)` / `@type=url`
- Default values after `=` (plain text, or `op(...)` for 1Password - see next step)

### 4. Wire up 1Password for secrets (if applicable)

**Two separate steps are required** - installing/registering the plugin is not enough:

1. `@plugin(@varlock/1password-plugin)` - registers the plugin (adds the `op()` function to the resolver table).
2. `@initOp(...)` - initializes an instance (without this you get `op(): No 1Password plugin instances found`).

The realistic dev-machine form (desktop-app auth, service-account fallback for CI):

```
# @defaultRequired=infer
# @defaultSensitive=true
# @plugin(@varlock/1password-plugin)
# @initOp(token=$OP_TOKEN, allowAppAuth=true, account=<shorthand>)
# ---

# 1Password service account token (leave empty locally → desktop app is used).
# @type=opServiceAccountToken
# @sensitive=true
# @required=false
OP_TOKEN=
```

Get the account shorthand from `op account list` - it's the subdomain of the sign-in URL (e.g., `my.1password.com` → `my`). The `op` CLI must be installed (`brew install 1password-cli`) AND desktop-app CLI integration enabled in 1Password → Developer settings. `op whoami` should succeed before you expect varlock to work.

For pure service-account (CI only, no desktop app), drop `allowAppAuth` / `account`:

```
# @plugin(@varlock/1password-plugin)
# @initOp(token=$OP_TOKEN)
# ---
# @type=opServiceAccountToken @sensitive
OP_TOKEN=
```

Reference any secret inline using `op(...)` (function-call form, **not** `op="..."`):

```
# @required @sensitive=true @type=string
API_KEY=op("op://VaultName/ItemNameOrUUID/fieldName")
```

### 5. Clean up files that are now redundant

- Delete `.env.example` - `.env.schema` supersedes it (commit the schema).
- If the schema provides defaults for everything (including `op(...)` refs for secrets), delete `.env`. Otherwise keep `.env` for local overrides - values there take precedence over schema defaults.
- Update any docs that mention dotenv (`CLAUDE.md`, architecture diagrams, onboarding notes).
- `.env` stays in `.gitignore` regardless.

### 6. Verify

```bash
pnpm exec tsx -e 'import "varlock/auto-load"; console.log("OK", !!process.env.YOUR_REQUIRED_VAR);'
```

On load varlock prints a config report (sources, resolved items, errors). If any `@required` var is missing it will crash loudly - that's the feature. Also run `pnpm build` to make sure TypeScript is still happy, then boot the app.

## Landmines (learned the hard way)

### Function-form decorators vs. assignment-form - they're not interchangeable

Varlock has two decorator shapes and the parser is strict about which one each decorator expects:

- **Assignment form** `# @name=value` - for flags/defaults like `@defaultRequired=infer`, `@sensitive=true`, `@type=string`, `@required=false`
- **Function form** `# @name(arg1, arg2=foo)` - for registering/initializing things: `@plugin(@varlock/1password-plugin)`, `@initOp(token=$OP_TOKEN, allowAppAuth=true)`, `@setValuesBulk(opLoadEnvironment(id))`

Symptoms if you mix them up:

```
.env.schema: @plugin must be used as a function call - use @plugin(...) instead of @plugin=value
```

When in doubt: anything that takes named args uses `@name(...)`; anything that's a single scalar config uses `@name=value`.

### Empty decorator assignments crash the parser

`# @initOp=` (no value) produces `Parse error: Expected ["], ['], [^# \n], ... but "\n" found.` - and because the whole schema fails to parse, every var looks empty and sensitive until you fix it. Use the function form with no args instead (`# @initOp()`) or delete the line entirely.

### Plugin registration ≠ plugin initialization

Installing `@varlock/1password-plugin` + adding `@plugin(...)` makes the `op()` function *recognizable*, but calling it still fails with `op(): No 1Password plugin instances found` until you also add `@initOp(...)`. Both decorators are required.

### `preventLeaks=true` (the default) silently kills scripts on any unresolved item

If *any* var in the schema fails to resolve (bad `op()` ref, missing plugin, typo, wrong type), varlock's `auto-load` refuses to populate `process.env` and exits the Node process during module load. Your script produces zero output and looks dead. Diagnosis:

- Run the script in foreground - you'll see the `🚨 Configuration is currently invalid` banner on stderr listing every offender
- Fix the failing items (or mark them `@required=false` if they're only needed conditionally)
- **One broken item blocks the whole process** - it's not "best-effort load what you can"

This is the most confusing varlock behavior. Expect it, look for it first when a varlock-loaded script unexpectedly produces nothing.

### Varlock's config report goes to stderr - it corrupts TUIs

When a script backgrounds a varlock-using helper and pipes its output into `lnav` / `less` / a TUI, the varlock validation dump (on stderr) leaks to the controlling terminal and visually garbles the TUI. Always redirect both streams:

```bash
pnpm run script helper.ts >> logs/out.log 2>&1 &
```

### `@description=` breaks the parser on certain characters

The schema parser chokes when the value of `@description=` contains `@` symbols (e.g. `@description=token from @BotFather`) and possibly other punctuation. The error looks like:

```
.env.schema: Parse error: Expected "#", "@", "\n", or [ \t] but "B" found.
```

**Workaround:** skip `@description=` entirely. Use plain `#` comment lines above the variable for documentation. Agents still read them, humans still read them, and the parser is happy.

```
# This works reliably.
# @required
# @sensitive=true
# @type=string
TELEGRAM_BOT_TOKEN=
```

### 1Password `op://` refs can't contain parentheses

The 1P CLI rejects secret references that contain `(`, `)`, or `%` - even URL-encoded forms:

```
invalid character in secret reference: '('
invalid character in secret reference: '%'
```

**Workaround:** reference the item by its UUID instead of its human name. Find the UUID:

```bash
op item list --vault Personal | grep -i <item-name-fragment>
# → vmu66ebovctrualql6cmdfmtbq    Telegram - Homebot - API key (token)    ...
```

Then use the UUID in the schema:

```
TELEGRAM_BOT_TOKEN=op("op://Personal/vmu66ebovctrualql6cmdfmtbq/notesPlain")
```

UUIDs are stable across renames, so this is also more robust than name references long-term.

### Decorators on the same line work but are fragile

The docs show `# @required @type=string @sensitive=true` as a single line. That works most of the time, but when something goes wrong it's hard to tell which decorator the parser barfed on. Put one decorator per line - easier to diff, easier to debug.

### Schema values vs. `.env` values

If both the schema has a default and `.env` sets the same variable, `.env` wins. When migrating, decide up front whether the schema or `.env` is the source of truth. Committing the schema with `op(...)` refs for secrets and deleting `.env` gives you a single source of truth that's safe to share.

### Sensitivity affects log redaction, not access

`@sensitive=true` marks a value for redaction in varlock's own output (and in `redactLogs` behavior). It does not encrypt the value or restrict who can read it from `process.env`. Mark genuine secrets sensitive to avoid accidentally printing them; mark non-secrets (IDs, paths) non-sensitive so varlock's config dump is actually readable while debugging.

## Reference: minimal working schema

For a small Node.js/TypeScript app with one 1Password-backed secret:

```
# @defaultRequired=infer
# @defaultSensitive=true
# @plugin(@varlock/1password-plugin)
# @initOp(token=$OP_TOKEN, allowAppAuth=true, account=<your-1p-shorthand>)
# ---

# 1Password service account token - empty locally (desktop app covers it), set in CI.
# @type=opServiceAccountToken
# @sensitive=true
# @required=false
OP_TOKEN=

# Telegram Bot API token (from BotFather)
# @required
# @sensitive=true
# @type=string
TELEGRAM_BOT_TOKEN=op("op://Personal/<item-uuid>/notesPlain")

# Comma-separated list of allowed chat IDs
# @required
# @sensitive=false
# @type=string
ALLOWED_CHAT_IDS=123,456

# Working directory for the agent
# @required
# @sensitive=false
# @type=string
AGENT_CWD=/Users/you/scripts

# Optional - if not set, fall back to `claude login`
# @optional
# @sensitive=true
# @type=string
ANTHROPIC_API_KEY=
```

## What to tell the user when you're done

Summarize the three things that changed:
1. **Dependencies**: `dotenv` out, `varlock` (and optionally `@varlock/1password-plugin`) in.
2. **Entrypoint**: `import "dotenv/config"` → `import "varlock/auto-load"`.
3. **Schema**: `.env.schema` is committed and describes every env var; `.env.example` is gone; `.env` is gone too if the schema carries all defaults.

Mention that `process.env.*` usage throughout the codebase still works, and that varlock will now loudly refuse to start if a `@required` var is missing - which is the whole point.
