---
name: free-disk-space
description: Find what is eating disk space on a Mac and safely reclaim it, with an interactive treemap colored by how safe each folder is to delete. Use whenever the user says the disk is full, "free up space", "clear drive space", "what's taking so much space", "clean my Mac", mentions ncdu/dust/gdu or low storage, or asks to clean caches, Docker, node_modules, build artifacts or old worktrees - even if they never say "treemap".
---

# free-disk-space

Scan the home directory, classify what is reclaimable, show it as a treemap, and delete only what the user approves. macOS only (paths like `~/Library` are hard-coded in the catalog).

## Flow

1. **Baseline.** `df -h /` so you can report before/after.
2. **Scan** (about 1-2 min for a few hundred GB; run it in the background and say so):
   ```bash
   python3 <skill-dir>/scripts/scan.py ~ -o /tmp/free-disk-space-tree.json
   python3 <skill-dir>/scripts/treemap.py /tmp/free-disk-space-tree.json -o /tmp/free-disk-space.html && open /tmp/free-disk-space.html
   ```
   The page is local and display-only: click a box to drill in, hover for a "copy cmd" button. Do not publish it as a claude.ai artifact; it contains the user's file paths.
3. **Report in the terminal too**, grouped by tier with sizes (use the JSON, largest first), so the user can decide without the browser:
   - `safe` (green): caches that re-download on demand.
   - `rebuildable` (amber): build output, `node_modules`, `.venv`, Docker, git worktrees. Free but costs a rebuild.
   - `decide` (red): the user's own data (Trash, recordings, Downloads, app data). Always the user's call.
   - `unknown` (gray): not in the catalog; look before suggesting anything.
4. **Propose, then wait.** List the exact paths and commands for what you would delete and the total size. Delete nothing until the user says yes to that list.
5. **Delete** with the entry's native cleaner when it has one (`uv cache clean`, `pnpm store prune`, `go clean -modcache`, `cargo clean`), else `rm -rf -- <exact path>`. Never use wildcards you have not expanded and shown.
6. **Report** `df -h /` after, and the GiB freed.

## Per-target care

- **Docker:** run `docker system df` and show it before `docker system prune -a --volumes`; volumes can hold databases.
- **Git worktrees:** use `git worktree list` in the owning repo and `git worktree remove`, not `rm`, and skip any with uncommitted changes or a name like `*-dont-remove`.
- **Rust `target/`, `node_modules`, `.venv`:** only delete if the project is not being built right now; mention the rebuild cost.
- **Trash, screen recordings, Downloads, app data:** list the largest items and ask per item. Large files in Downloads (`.dmg`, `.zip`, meeting recordings) are common wins.
- **Browser profiles / app data (Arc, Steam, MacWhisper models, TimeSnapper):** deleting logs the user out or loses data; recommend only if they confirm they no longer use the app.

## Guardrails

Never delete or suggest deleting: `~/Library/Keychains`, `~/Library/Mobile Documents` (iCloud), `~/.ssh`, `~/.gnupg`, `~/Library/Messages`, `~/Library/Photos`. The scanner tags these `protected` and the treemap shows no copy button for them.

## Extending the catalog

`targets.json` maps a home-relative glob (`path`) or a basename (`name`) to a tier, a note and an optional native `cmd`. Later entries override earlier ones, so put specific paths after generic globs. When the user teaches you a new safe-to-clear location, add it there.
