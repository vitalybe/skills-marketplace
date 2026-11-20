---
name: alfred-workflow
description: How to create and modify Alfred workflows programmatically. Use whenever the user asks to create, edit, or debug an Alfred workflow, keyword, script filter, hotkey trigger, or Alfred UI (.alfredui native UI toolkit, ui.json). Also use when you see Alfred-related files like info.plist inside an Alfred workflow directory, or when the user references Alfred keywords, snippets, or universal actions.
---

# Alfred Workflow Authoring

Alfred workflows are defined by an `info.plist` file (XML plist) inside a workflow bundle directory. The plist describes a directed graph of nodes (objects) connected by edges (connections).

## Workflow Structure

```
user.workflow.<UUID>/
  info.plist      # Workflow definition (XML plist)
  icon.png        # Workflow icon
  *.png           # Additional icons for specific nodes
  scripts/        # Optional external script files
```

## info.plist Top-Level Keys

| Key | Type | Purpose |
|-----|------|---------|
| `bundleid` | string | Unique bundle identifier |
| `name` | string | Workflow display name |
| `description` | string | Short description |
| `disabled` | boolean | Whether workflow is disabled |
| `objects` | array | All workflow nodes (triggers, actions, etc.) |
| `connections` | dict | Edges between nodes, keyed by source UID |
| `uidata` | dict | Visual positions (xpos/ypos) for each node |
| `version` | string | Workflow version |
| `readme` | string | Longer description |
| `createdby` | string | Author name |
| `webaddress` | string | Author URL |
| `variablesdontexport` | array | Variables to exclude from export |

## Objects (Nodes)

Each object has a `type`, `uid`, `version`, and `config` dict. Common types:

### Script Filter (`alfred.workflow.input.scriptfilter`)
Keyword-triggered input that runs a script and displays results in Alfred.

```xml
<dict>
    <key>config</key>
    <dict>
        <key>keyword</key>
        <string>mykeyword</string>
        <key>alfredfiltersresults</key>
        <true/>
        <key>argumenttype</key>
        <integer>1</integer>
        <key>withspace</key>
        <true/>
        <key>script</key>
        <string>your script here</string>
        <key>scriptargtype</key>
        <integer>1</integer>
        <key>type</key>
        <integer>0</integer>
        <key>title</key>
        <string>Display Title</string>
        <key>subtext</key>
        <string>Subtitle text</string>
        <key>escaping</key>
        <integer>102</integer>
        <key>queuedelaymode</key>
        <integer>0</integer>
        <key>queuemode</key>
        <integer>1</integer>
        <key>runningsubtext</key>
        <string></string>
        <key>scriptfile</key>
        <string></string>
        <key>queuedelaycustom</key>
        <integer>3</integer>
        <key>queuedelayimmediatelyalinitially</key>
        <true/>
    </dict>
    <key>type</key>
    <string>alfred.workflow.input.scriptfilter</string>
    <key>uid</key>
    <string>SOME-UUID-HERE</string>
    <key>version</key>
    <integer>3</integer>
</dict>
```

Key config fields:
- `keyword`: Trigger keyword. Use `||` to support multiple keywords (e.g., `dp||dropover`)
- `alfredfiltersresults`: `true` lets Alfred handle fuzzy filtering client-side
- `argumenttype`: 0=required, 1=optional, 2=none
- `withspace`: Whether a space follows the keyword before arguments
- `scriptargtype`: 0=query via `{query}` placeholder, 1=query via argv
- `type`: Script language - 0=bash, 1=perl, 2=ruby, 3=python, 4=php, 5=zsh, 6=osascript/JS
- `escaping`: Bitmask for character escaping (102 is a common default)

### Run Script (`alfred.workflow.action.script`)
Executes a script when triggered.

```xml
<dict>
    <key>config</key>
    <dict>
        <key>concurrently</key>
        <false/>
        <key>escaping</key>
        <integer>102</integer>
        <key>script</key>
        <string>your script here</string>
        <key>scriptargtype</key>
        <integer>1</integer>
        <key>scriptfile</key>
        <string></string>
        <key>type</key>
        <integer>0</integer>
    </dict>
    <key>type</key>
    <string>alfred.workflow.action.script</string>
    <key>uid</key>
    <string>SOME-UUID-HERE</string>
    <key>version</key>
    <integer>2</integer>
</dict>
```

### Action Trigger (`alfred.workflow.trigger.action`)
Triggered by Alfred's Universal Actions (e.g., file actions).

### Other common types
- `alfred.workflow.input.keyword` - Simple keyword trigger (no script)
- `alfred.workflow.trigger.hotkey` - Hotkey trigger
- `alfred.workflow.output.notification` - Show notification
- `alfred.workflow.utility.filter` - Conditional filter
- `alfred.workflow.utility.conditional` - Branch on a variable (see below)
- `alfred.workflow.action.openurl` - Open URL
- `alfred.workflow.action.openfile` - Open file
- `alfred.workflow.userinterface.alfredui` - Native custom UI (see "Alfred UI" below)

### Conditional (`alfred.workflow.utility.conditional`)

Branches the flow based on a variable's value. Each `condition` has an `outputlabel`; the condition with `elselabel` is the default branch. Routing to downstream nodes is determined by matching the connection's `modifiersubtext` against the condition's `outputlabel` — get this wrong and everything silently falls through (or nothing fires at all).

```xml
<dict>
    <key>config</key>
    <dict>
        <key>conditions</key>
        <array>
            <dict>
                <key>inputstring</key>
                <string>{var:action}</string>
                <key>matchmode</key>
                <integer>0</integer>             <!-- 0=equals, 1=startswith, 2=contains, 3=regex -->
                <key>matchstring</key>
                <string>delete</string>
                <key>outputlabel</key>
                <string>delete</string>          <!-- must match the connection's modifiersubtext -->
                <key>uid</key>
                <string>DELETE-NODE-UID</string>
            </dict>
        </array>
        <key>elselabel</key>
        <string>open</string>                    <!-- must match the default connection's modifiersubtext -->
    </dict>
    <key>type</key>
    <string>alfred.workflow.utility.conditional</string>
    ...
</dict>
```

**Trap**: when an item flowing into the conditional doesn't set the routing variable, `{var:action}` substitutes to an empty string and ends up on the `elselabel` branch. That's almost always what you want — but if you ever need a "no variable set" branch distinct from a "wrong value" branch, use a sentinel default like `variables: { action: "open" }` on every item.

## Connections

The `connections` dict maps source object UIDs to arrays of destination objects:

```xml
<key>connections</key>
<dict>
    <key>SOURCE-UID</key>
    <array>
        <dict>
            <key>destinationuid</key>
            <string>DEST-UID</string>
            <key>modifiers</key>
            <integer>0</integer>
            <key>modifiersubtext</key>
            <string></string>
            <key>vitoclose</key>
            <false/>
        </dict>
    </array>
    <!-- Terminal nodes need an empty array -->
    <key>TERMINAL-UID</key>
    <array/>
</dict>
```

Every object UID should appear as a key in connections, even terminal nodes (with an empty array).

## Script Filter JSON Output

Script Filters output JSON to stdout. Alfred renders the items as a list.

```json
{
  "items": [
    {
      "uid": "unique-id",
      "title": "Display Title",
      "subtitle": "Secondary text",
      "arg": "value-passed-to-next-node",
      "icon": {"path": "icon.png"},
      "match": "extra keywords for filtering",
      "valid": true,
      "autocomplete": "tab-completion text",
      "mods": {
        "alt": {"valid": true, "arg": "alt-arg", "subtitle": "alt subtitle"}
      }
    }
  ]
}
```

When `alfredfiltersresults` is true, the `match` field replaces `title` for filtering purposes - add extra keywords there to improve discoverability.

Useful but easy-to-miss item fields:
- `autocomplete`: when the user presses Tab on this item, Alfred fills the search bar with this string. Great for "restore previous draft / restore last query" patterns where you want the user to *edit* a stored value rather than just send it.
- `quicklookurl`: a `file://...` URL (or http) that Alfred opens in a Quick Look panel when the user presses Shift. Pair it with a generated HTML file (saved per item to `/tmp/...html`) for rich right-side previews — much nicer than cramming everything into a subtitle.
- `text.copy` / `text.largetype`: the strings used by ⌘C and ⌘L respectively, independent of the item's `arg`.
- `variables`: a dict that becomes available downstream as `{var:name}`. Per-modifier `mods.<key>.variables` overrides the defaults when that modifier is held.

## uidata (Visual Layout)

Positions for the Alfred workflow editor canvas:

```xml
<key>uidata</key>
<dict>
    <key>NODE-UID</key>
    <dict>
        <key>xpos</key>
        <integer>145</integer>
        <key>ypos</key>
        <integer>285</integer>
    </dict>
</dict>
```

Place connected nodes left-to-right with ~180px horizontal spacing. Stack parallel paths vertically with ~200px spacing.

## Tips

- When writing scripts inside plist XML, remember to escape `<` as `&lt;`, `>` as `&gt;`, and `&` as `&amp;`. Curly braces, quotes, and most other characters don't need escaping inside `<string>` elements.
- **Prefer external script files over inline scripts.** Put logic in `search.py` / `search.sh` next to the plist and set the script config to `python3 ./search.py "$1"`. Inline scripts silently break when they contain `<`, `>`, or `&` (e.g. Python comparisons, HTML parsing, bash heredocs). You also lose syntax highlighting and the ability to test the script standalone.
- Test the script directly before wiring it up: `python3 search.py "some query" | python3 -m json.tool`. This catches JSON errors that would otherwise show as silent failures in Alfred.
- Validate the plist after editing: `plutil -lint info.plist`.
- Use `printf` for inline JSON output in bash scripts to avoid heredoc escaping issues in plists.
- The `icon.png` at the workflow root is used as the default icon. Reference it in JSON items as `{"path": "icon.png"}`.
- Alfred's official docs: `https://www.alfredapp.com/help/workflows/`
- Script Filter JSON format: `https://www.alfredapp.com/help/workflows/inputs/script-filter/json/`

## Script Filter Behavior (Gotchas)

These are non-obvious defaults that cost real debugging time if you don't know them:

- **Previous results stay visible while the script re-runs.** Alfred does NOT clear the list when a new keystroke fires the script. It replaces items only when the new script outputs. The `runningsubtext` appears at the top as a status line, but old items remain. To force-clear immediately, use the `rerun` pattern below.
- **`alfredfiltersresults: true` filters cached items client-side by the typed query.** Set it to `false` when items are not plain searchable text (emojis, images, pre-sorted API results), otherwise Alfred will hide items whose `title`/`match` don't contain the typed text — even items the script just returned. When this is wrong, typing a query makes the workflow appear to "fall through" to default Alfred fallbacks (Google/Amazon/etc.).
- **`queuemode: 2`** (terminate previous) kills an in-flight script when a new keystroke arrives. This is the cleanest way to implement natural debounce for network-bound script filters.
- **`queuedelaymode`**: `0`=automatic, `1`=immediate on every keystroke, `2`=custom delay (uses `queuedelaycustom` in tenths of a second). The automatic/custom modes add a wait BEFORE firing the script, during which old results stay visible — so they aren't a substitute for clearing results.
- **`rerun`** (JSON output field, 0.1–5.0 seconds): tells Alfred to re-run the script after N seconds. This is how you implement a proper loading state that also does its own debounce (see pattern below).

## Pattern: Debounce + Loading State for Network Script Filters

Problem: you want to show "Searching..." immediately when the user types, then fetch results only after they stop typing.

Key config:
```
queuedelaymode = 1       # immediate — fire on every keystroke
queuemode = 2            # terminate previous
alfredfiltersresults = false
```

Script logic (state file in `$alfred_workflow_cache`):
1. Read `{last_query, fetched}` from state file.
2. If query changed: write `{query, fetched: false}`, output `{"rerun": 0.3, "items": [{"title": "Searching...", "valid": false}]}` and exit. This clears old items and queues a rerun.
3. If query unchanged and `fetched == false`: write `{query, fetched: true}`, do the actual fetch, output results.
4. If query unchanged and `fetched == true`: do nothing / output cached.

Each keystroke resets the rerun timer (step 2). Only when the user stops typing for 300ms does the rerun fire the fetch (step 3).

## Common Mistakes

- **Editing inline scripts that contain `<` or `>` characters.** They get XML-escaped on save and silently corrupt the script (`find('>')` becomes `find('&gt;')`). Use an external script file.
- **Leaving `alfredfiltersresults: true` for non-text results.** Causes items to disappear as the user types, with the workflow appearing to fall through to Alfred's default web-search fallbacks. Default it to `false` unless items are plain searchable text.
- **Expecting Alfred to clear results while a new script runs.** It doesn't. Use the `rerun` pattern above if you need a visible loading state.
- **Using `queuedelaymode` alone for debounce.** The delay just holds off firing the script; stale results keep showing during the wait. Combine with `queuemode: 2` and/or the `rerun` pattern.
- **Not setting terminal-node empty arrays in `connections`.** Every object UID must appear as a key, even leaves (with an empty `<array/>`).
- **Forgetting `withspace: true` on a keyword that takes an argument.** With `withspace: false`, Alfred treats the typed text as part of the keyword for matching, so the argument never reaches the script. Set `withspace: true` whenever `argumenttype` is 0 or 1.

## Environment & data dirs

Alfred runs scripts with a deliberately minimal environment — your shell's rc files (`.zshrc`, `~/.config/fish/config.fish`, etc.) do **not** run, so user PATH additions like `~/.local/bin`, Homebrew bin dirs, and language-version managers (mise, asdf, nvm) are missing by default. Tools that you assume "are obviously in PATH" because they work in your terminal will be silently `command not found` when Alfred runs them. The failure mode is "Enter does nothing" — Alfred swallows the script's stderr.

Source a shared `common.sh` from every script in the workflow that exports a known-good PATH:

```bash
# scripts/common.sh
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
```

When debugging "Enter does nothing", the first thing to check is `which <tool>` from the workflow dir under that exact PATH.

Alfred provides several env vars to scripts:
- `$alfred_workflow_data` — persistent per-workflow data dir. Created on demand. Survives workflow updates and re-imports. **Use this for sidecar JSONs, drafts, etc.**
- `$alfred_workflow_cache` — same shape, but ephemeral; safe to nuke from the user side.
- `$alfred_workflow_bundleid`, `$alfred_workflow_uid`, `$alfred_workflow_version` — metadata.
- `$alfred_preferences` — path to `Alfred.alfredpreferences`.

**Never** write to the workflow bundle directory itself. It's intended to be exportable / re-importable, and on shared machines may be read-only.

When testing a script standalone, set `alfred_workflow_data` manually:
```bash
export alfred_workflow_data="$HOME/Library/Application Support/Alfred/Workflow Data/<bundleid>"
./scripts/foo.sh "test arg"
```

## Background tasks (fire-and-forget)

Alfred waits for the script to finish before unblocking. For long-running side work (network calls, file processing, naming/tagging via an LLM), spawn a detached process so Alfred returns instantly:

```bash
nohup "$DIR/heavy_task.sh" "$arg" >/dev/null 2>&1 &
disown
```

Without `disown`, fish/zsh may keep the parent alive waiting for the child. Without `>/dev/null 2>&1`, output to a closed Alfred TTY can SIGPIPE the child mid-flight.

## JSON accumulation in bash (Script Filter pitfall)

A common Script Filter shape is "loop over N records, build an Alfred item per record, emit `{items: [...]}`". The naive accumulator pattern is dangerous:

```bash
items='[]'
for f in *.json; do
  item="$(jq -n ... '<build $item>')"
  items="$(printf '%s' "$items" | jq --argjson item "$item" '. + [$item]')"  # FRAGILE
done
echo "{\"items\": $items}"
```

This breaks the moment a single iteration produces an empty or invalid `$item` (preview script failed, source file was zero-byte, network call timed out): the inner `jq --argjson item ""` errors out, `items` is silently set to the empty string, and **every previously accumulated item is lost**. The user sees "no results" with no error.

Robust pattern — write each item to a temp file, then slurp:

```bash
TMPDIR_ITEMS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ITEMS"' EXIT

for f in *.json; do
  jq -n ... '<build item>' > "$TMPDIR_ITEMS/$(basename "$f")"
done

jq -s '{items: .}' "$TMPDIR_ITEMS"/*.json
```

A failed iteration leaves a missing or corrupt file that you can `find -size 0 -delete` or skip with `jq -e .` per file before slurping. The other iterations are unaffected. Bonus: easier to inspect after the fact — you can `cat` the temp dir during a debug run.

Related gotchas:
- `jq empty` returns **exit 0 on empty stdin** — it's not a JSON validity check. Use `jq -e . >/dev/null 2>&1 || continue` (or `[ -z "$var" ] && continue` first) to skip empty/non-JSON inputs.
- `--argjson foo ""` errors out with `invalid JSON text passed to --argjson`. Always validate the value is non-empty + well-formed before passing it.

## Multi-line input

Alfred's keyword bar is single-line. If the user genuinely needs paragraph-length input (a journal entry, a chat message draft, a code snippet), don't try to fake it inside Alfred — open a real editor.

Pattern that works well: keyword `foo` with `argumenttype: 1` (optional). If `$1` is non-empty, send it directly (fast path). If empty, spawn a terminal window running the user's `$EDITOR` on a draft file at `~/.cache/alfred-foo-draft.md`, with a tiny wrapper around it that, after the editor exits, prints a `↵ send / k keep / x clear / e re-edit` prompt.

```bash
[ -n "$QUERY" ] && exec "$DIR/send.sh" "$QUERY"

mkdir -p "$(dirname "$DRAFT")"
[ -e "$DRAFT" ] || : > "$DRAFT"

# Spawn in a separate window so the user can keep using Alfred / their other apps
open -na Ghostty.app --args -e "$DIR/compose.sh" "$DRAFT"
```

The draft file gives you free persistence across ESCs, Alfred restarts, and reboots — much better than trying to keep state inside Alfred itself.

## Launching macOS apps with arguments

To open a fresh window of a GUI app from a workflow script, the right macOS incantation is:

```bash
open -na <App>.app --args <argv...>
```

`-n` forces a new instance (rather than re-using/raising an existing window). `-a` selects the app. Everything after `--args` is passed as argv.

Some terminal apps consume "everything after `-e`" as the inner command:
```bash
open -na Ghostty.app --args -e tmux attach -t 'my session'
```
Do **not** quote the `-e` payload as a single string. Each argv element is passed literally; Ghostty (and similar) will tokenize them itself.

## Alfred UI (native UI toolkit)

Alfred UI lets a workflow show a native macOS UI (buttons, text fields, lists, web views...) described entirely in JSON, with no compilation. Docs: `https://www.alfredapp.com/help/alfredui/` (sub-pages: `window/`, `layouts/`, `components/`, `events/`, `actions/`, `actions/json/`, `variables/`, `placeholders/`, `templates/`, `tutorials/`). Real examples to copy from: the "Try Alfred UI" and "Text Transformer" workflows (`alfred.app/workflows/alfredapp`). Alfred UI is not the workflow canvas and not theming.

### Workflow object

A workflow object points at a `.alfredui` package folder inside the workflow bundle. Connect a keyword input or hotkey trigger to it (no argument needed; the keyword's argument, if any, arrives as `args[0]`).

```xml
<dict>
    <key>config</key>
    <dict>
        <key>path</key>
        <string>my-ui.alfredui</string>   <!-- relative to the workflow dir -->
        <key>stackview</key>
        <false/>                          <!-- "Stacking": Esc returns to previous Alfred view -->
        <key>launchmode</key>
        <integer>0</integer>              <!-- 0 = open within Alfred, 1 = launch externally (own window) -->
    </dict>
    <key>type</key>
    <string>alfred.workflow.userinterface.alfredui</string>
    <key>uid</key>
    <string>SOME-UUID-HERE</string>
    <key>version</key>
    <integer>1</integer>
</dict>
```

`launchmode` values are inferred from shipped workflows (Text Transformer = 0, in Alfred; Try Alfred UI = 1, standalone window). Like every object it needs a `connections` key and `uidata` entry.

### Package layout

```
my-ui.alfredui/
  ui.json          # required, exactly this name
  components/*.json  # optional, pulled in with "{file:components/x.json}"
  scripts/*          # optional, paths in actions are relative to the .alfredui root
  resources/*        # optional images/sounds
```

### ui.json

```json
{
  "bundleid": "com.me.myui",
  "variablesconfig": { "input": { "src": "args[0]" } },
  "window": {
    "title": "My UI",
    "size": { "width": 600, "height": 400 },
    "padding": 8,
    "root": {
      "type": "view",
      "layout": "inline",
      "spacing": 8,
      "components": [
        { "id": "field", "type": "textfield", "placeholder": "Type...", "focus": true },
        {
          "type": "button", "text": "Go",
          "events": [{
            "triggers": "actioned",
            "action": { "type": "script", "src": "scripts/go", "args": ["{value:field.text}"] }
          }]
        }
      ]
    }
  }
}
```

- Top-level keys: `bundleid` (needed for variable persistence), `window`, `variables`, `variablesconfig`, `templates`, `colours`, `iconpath` (external only), `log`, `debug`, `pulse`.
- `window`: `root` (required, usually a `view`), `title`, `size`, `padding`, `blur`, `appearance`, `toolbar`, `borderless`, `frameautosave` (external only).
- Layouts (`view.layout`): `stack` (default), `border` (child `constraints.region`: top/centre/right/...), `grid` (`rows`, `cols`), `inline`, `form`, `flex` (child `constraints.grid.row/col`, `constraints.size`).
- Components: `view`, `label`, `button`, `checkbox`, `picker`, `textfield`, `passwordfield`, `textarea`, `markdownarea`, `progress`, `imageview`, `dataview`, `webkitview`, `template`. Give a component an `id` to read or update it later.
- `shortcuts` on a view: `[{ "shortcut": "⌘↩", "action": {...} }]`, only active when a descendant has focus.

### Events and actions

Component `events`: `[{ "triggers": "actioned", "action": {...} }]`. Triggers: `preload`, `launched`, `quit`, `actioned` (default), `changed`, `typingstopped`, `mousedown`, `mouseup`, `clicked`, `doubleclicked`. Events run on the UI thread, so a slow script freezes the UI: return fast or set `"async": true`.

Action `type`:
- `script`: `src` = script path, `args` = argv. The script's stdout is parsed as a JSON action (same shape as `json`'s `src`), so a script can update the UI. Variables flagged `scriptenv: true` arrive as env vars.
- `json`: `src` = inline object or a path to a JSON file. Commands, in processing order: `remove, insert, update, replace, sheet, share, sound, speak, copy, open, opendialog, window, notification, functions, popupmenu, finish`.
- `function`: `src` = component id, `args` = function name (e.g. `"selectnext"`, `"filterdata"`; window: `close`, `zoom`, `minimise`).
- `log`: logs `args`.

Updating components from JSON/script output: `{"update": {"ids": {"field": {"focus": true}}}}`, `{"update": {"relayout": true, "ids": {...}}}`.

`finish` ends the UI and hands control back to the workflow, so downstream nodes (copy to clipboard, open URL, ...) fire: `{"finish": {"args": "{value:field.text}", "variables": {"mode": "paste"}}}`. `args` becomes `{query}` for the next node and `variables` become `{var:...}`. Branch on them with a Conditional node.

### Variables and placeholders

- `{var:name}`: a variable (set in `variables`, via an action's `variables`, or from `variablesconfig`).
- `variablesconfig.<name>`: `default`, `persist` (saved across launches, needs `bundleid`), `scriptenv` (exported to scripts), `src` (`args[0]` = launch argument, `args` = all, `variable` = workflow variable; workflow variables are NOT loaded unless `src: "variable"`).
- `{const:name}`: workflow constant. `{file:path}`: inline another JSON file (further processed). `{fileraw:path}`: inline without processing (big data).
- Dynamic, resolved when an action fires: `{value:componentId.property}` (e.g. `field.text`, `list.selected.name`), `{data:prop}` (dataview cell), `{param:name}` (inside a template).
- A lone placeholder keeps its type (object, bool); embedded in a string it becomes a string.
- Not preprocessed: `bundleid`, `variablesconfig`, `variables`, `args`, `action.src`, `data.filter`.

### Tips

- Write `ui.json` by hand, split big parts into `components/*.json` with `{file:...}`. No plist escaping issues, unlike inline scripts.
- Scripts can be any executable with a shebang (the shipped examples use `#!/usr/bin/osascript -l JavaScript` and zsh). `chmod +x` them. The same minimal-PATH rules as other workflow scripts apply.
- Paste `ui.json` snippets into the "Try Alfred UI" workflow to preview live while iterating.
- Validate with `jq . ui.json` and `plutil -lint info.plist`.
- Only `view` and `button` property tables were verified from the docs; for other components (`textfield`, `dataview`, `webkitview`, ...) read `components/<name>/` before relying on a property.
