# Validation (fallback)

Used when the project doesn't define `docs/validation-procedure.md`.

1. Read `package.json` (each workspace's, in a monorepo) and identify
   the validation scripts it defines. Typical names: `typecheck`,
   `lint`, `test`, `build`, `check`.
2. Run the ones that exist, in that order. Skip missing ones - don't
   invent scripts or run tools that aren't wired up.
3. All must exit 0. On failure: fix, get user approval for the fix,
   commit, and re-run from step 2.

If `package.json` defines none of these, say so and ask the user what
validation applies - don't guess.
