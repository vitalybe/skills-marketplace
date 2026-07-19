# Developer Guidelines

## Code Style

- Don't use `null` for optional values, use `undefined` instead
- Avoid using `any` type, if possible
- Avoid using `as unknown as` type castings, if possible. Consult the user if you need to use it.
- Prefer required parameters over optional, e.g. `param: object | undefined` over `param?: object`. Use optional parameters only when these parameters are not sent in most of the cases.
- Function should have a single return statement. Multiple return statements are an exception for very long functions and initial very short returns, e.g. 1-3 lines at the top to save huge if blocks. Otherwise, use a `let result` variable that you return at the end. For React components, extract conditional content into a variable instead of duplicating the wrapper JSX across multiple returns.
- Use `//` comments, not `/* */` or JSDoc (`/** */`). Keep comments minimal -- only add them where the logic isn't self-evident. Remove verbose documentation comments.
- Avoid `Array.reduce` unless it genuinely shortens the code. Prefer `filter`, `map`, `flatMap`, or a simple `for` loop for clarity.
- Always brace `if` / `else` / `for` / `while` bodies, even single-statement ones. No `if (cond) doThing();` or `if (cond) return;` on one line, and no brace-less `else`.
- When creating utility modules with exposed global functions, prefer wrapping them in a class with static methods rather than loose exported functions. Module-level state (e.g. Reanimated shared values) stays at module level for compatibility, but the public API should go through the class.

```ts
// Module-level state stays here for compatibility
const sharedValue = makeMutable(0);

export class MyUtils {
  static doSomething() { ... }
  static useAnimatedValue() { ... }
}
```

## Naming

- When an object field or interface property is a function, name it with a verb (e.g. `getImporter`, `execTask`), not a bare noun (e.g. `importer`, `task`). This distinguishes callable fields from data fields at a glance.
- The verb should describe what the caller receives, not what the function does internally. For callback/hook fields, name them so they read naturally at the call site: `getPostImportCallback` yields `const postImportCallback = entry.getPostImportCallback()` - clear when later used as `if (postImportCallback) { await postImportCallback(); }`.

## File Naming

All file and directory names use **camelCase** (e.g., `dataSourceRegistry.ts`, `dataSources/`).

Exceptions:

- Single-word lowercase names are fine (`types.ts`, `db.ts`, `index.ts`)
- Underscore-prefixed directories for internal modules (`_hooks/`, `_utils/`, `_parts/`)
- Config files follow their ecosystem conventions (`package.json`, `tsconfig.json`)
- npm script keys use kebab-case (`data-pull`, `merge-me`)

## Function Design

- Functions should be small (under 50 lines), perform a single task, and have few parameters (ideally 3 or less)
- Use explicit return types

## Clean Code

- **Code Organization**: Separate concerns (business logic, data access), group related functions, and prefer pure functions without side effects
- **Type Safety**: Use strict typing, avoid `any`, and handle nulls explicitly
- **Code Style**: Adhere to DRY principles, use descriptive naming, extract constants, and comment only complex logic

## Code Organization

### Prefer classes with static methods over exported module-level functions

When a module exposes multiple related functions, group them as static methods on a class rather than exporting standalone functions. This keeps related logic discoverable and avoids polluting the module scope with loose functions.

Standalone exported functions are acceptable only when they are truly unrelated to any other function in the module.

```ts
// ✅ Good - related functions grouped on a class
export class Db {
  static init(): void {
    /* ... */
  }
  static get(): Database {
    /* ... */
  }
  static close(): void {
    /* ... */
  }
}

// ❌ Avoid - loose related functions
export function initDb(): void {
  /* ... */
}
export function getDb(): Database {
  /* ... */
}
export function closeDb(): void {
  /* ... */
}
```

### Logger

Use `Logger` from `@ai-enablement/commons` instead of raw `console.*` calls. Each module creates an instance with a descriptive name:

```ts
import { Logger } from '@ai-enablement/commons';
const logger = new Logger('my-module');
logger.log('message');
```

### Date/Time

Use `luxon` `DateTime` instead of raw `Date` / `Date.now()`. Key patterns:

- Today's date: `DateTime.now().toISODate()!`
- ISO timestamp: `DateTime.now().toISO()!`
- N days ago (date): `DateTime.now().minus({ days: n }).toISODate()!`
- Epoch millis: `DateTime.now().toMillis()`

### Use TypeScript `private` over ES2022 `#` private fields

Use TypeScript's `private` keyword for class member visibility. Avoid ES2022 `#` private fields.

```ts
// ✅ Good
private static instance: Database | null = null;

// ❌ Avoid
static #instance: Database | null = null;
```

## Git

- **Always rebase, never merge, when syncing with `main`.** Use `git pull --rebase origin main` (or `git rebase origin/main`). Do not use `git pull` without `--rebase`, and do not run `git merge main` on a feature branch -- it pollutes history with merge commits.
- After rebasing a pushed branch, push with `git push --force-with-lease` (never plain `--force`).
- PRs are merged into `main` via the merge button (`gh pr merge --merge`), not squash or rebase -- the linear history per branch is preserved by the local rebase workflow above.
