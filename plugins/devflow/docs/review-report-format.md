# Review report format

A review report lists its items (findings, deltas, etc.) as one `###` block
each, ordered by severity. Head each block with its severity emoji, its `Q<n>`
id, and a title that states the situation as a sentence - not a defect
noun-phrase (`Someone approves the gate, but the agent has already finished`,
not `Stale approval race`). Beneath it, render each field as its own paragraph
led by its bold label, with a blank line between fields - never a markdown
table, never a bullet list of fields. The options are the one exception: they
are a bulleted list under the **Options.** label, one option per line. Close
with a `<sub>Technical: ...</sub>` footnote and separate blocks with `---`.
Whitespace is load-bearing here - the report is read to make decisions from, not
skimmed.

Prefix each finding's title with a short id `Q<n>` (`Q1`, `Q2`, ...), numbered
sequentially across the whole findings list - starting at `Q1` at the top
severity and continuing unbroken down through the lower ones - so the user can
reference any item by its id (e.g. `Q1 - Someone approves the gate, but the
agent has already finished`). The Q-ids cover the findings/Decision-needed list
only, not the Applied-fixes one-liners.

These are also the gate-package question ids: a report presented at a gate asks
for a decision per finding, and the answers come back keyed by these same ids.

## Severity

- 🔴 **Critical** - blocks the artifact from working.
- 🟠 **High** - silent breakage; works but the intent fails on a realistic path.
- 🟡 **Medium** - robustness, clarity, or completeness; can ship without it.
- 🟢 **Low** - polish, wording, style.

Order items by severity, highest first, and carry the emoji in each item's
heading. No tier headers - the emoji is the grouping. When one list mixes item
kinds (e.g. code findings alongside plan↔code deltas), tag each item inline with
its kind - e.g. a `(plan delta)` suffix on the title - so the mixed list stays
unambiguous. The invoking skill may add a one-line domain gloss, but the emoji
and their meanings are fixed.

## Writing a finding

Every field except the Technical footnote is written in product terms: what the
finding means for the product, not what it means for the code. A reader who has
never opened the repo must be able to answer the question.

- **Issue.** What happens, and the decision it forces - the situation from the
  product's side, then the choice being put to the user. Keep code out of it:
  no file paths, no symbol names above the footnote.
- **Why it's not already fixed.** One sentence on why the agent is asking
  instead of just doing it - out of scope, needs a call only the user can make,
  changes a contract, or the reviewers disagreed. Never "it seemed risky":
  name the thing that made it a decision.
- **Options.** Two to four choices as a bulleted list, one per line, each
  opening with `**(a) Short name.**` - a 1-3 word name that doubles as the
  answer label - then what that choice costs. When an option
  changes the **API contract, the storage model, or the UX**, float that here -
  still in product terms where it can be ("every client reading this field
  changes its assumption", "costs a column and a migration"). Offer an honest
  do-nothing option ("ship it and see", "leave it") whenever one exists.
- **If we don't pick.** What goes wrong while this stays open.
- **Technical.** The one place code lives: locations (linkified as
  `[file.ts:123](path/to/file.ts:123)`), symbols, and the reviewer source(s).
  Render as `<sub>Technical: ... Source: ...</sub>`.

Keep it short. The whole finding fits on a screen: **Issue** at most four
sentences, **Why it's not already fixed** exactly one, each **Options** entry at
most two, **If we don't pick** one or two, the footnote two or three. If a field wants more, either it is two findings or
the surplus belongs in the footnote. Reviewer disagreements resolve into the
options - they are not narrated.

Write short declarative sentences in the product's own vocabulary: the label on
the button someone clicks, the name of the screen, the word the team already
says out loud. "Keep code out of it" bans identifiers and paths, not the real
nouns - `the user ticks "Approve & unblock" and the task is already done` beats
`a sign-off arrives for a run the platform already considers complete`. Never
invent a paraphrase to avoid naming something that already has a name.

Tell the **Issue** as a short sequence of concrete events in the present tense,
then close it with the question in one sentence.

A purely technical finding still gets a product-level **Issue** - state the
architectural consequence as what it costs the product later ("duplicated logic
that has to be kept in sync every time we change feature X"), never as a rule
citation ("violates DRY").

Close the report with a one-paragraph **Quick read.** saying which items
genuinely need an answer and which are how-much-machinery calls.

## Apply / Decision needed triage

When triaging findings, sort each into **Apply** (clear issue, unambiguous fix)
or **Decision needed** (out of scope, stylistic, or a judgment call for the
user). Don't apply changes you don't understand - when in doubt, mark it
Decision needed and surface it.

Applied fixes are **not** part of the severity breakdown. Mention them briefly -
one line each - under an **Applied fixes** heading *before* the breakdown, then
give the full breakdown for the **Decision needed** items only. If nothing was
applied, write "Applied fixes: none." (In the flow's review phases the breakdown
goes to the plan file, not to chat - see below.)

## Source attribution

When findings come from more than one reviewer (see the review roster), name the
reviewer id(s) that raised each finding in its Technical footnote. When several
reviewers raised the same defect, list them together as corroboration (e.g.
`Source: official-anthropic-review-skill, codex`). Omit it entirely for
single-reviewer reviews where attribution adds nothing.

## Recording review outcomes in the plan

The flow's review steps (`_internal-step-plan`, `_internal-step-code`) also
record the review in the plan file - and for those steps the plan is the *only*
place the finding bodies go: the gate names them by id and the question the user
gets carries the body read back from the plan. The plan entries reuse the
severity emoji, `Q<n>` ids, fields, and footnote above, so a finding carries the
same id in the plan, at the gate, and in the answers coming back.

**Findings go one heading level deeper in the plan.** A chat report heads each
finding at `###`, but in the plan they sit inside `### Unhandled` or `###
Handled`, so head them at `####` there - at `###` they render as siblings of
`### Unhandled` and fall out of the section that owns them. Nothing else about
the block changes.

- **Applied findings never enter the plan.** Findings the agent fixed itself
  (the Apply tier) appear in the chat report only.
- **Decision-needed findings are written to `### Unhandled`** before they go to
  the user - under `## Plan review findings` for a plan review, `## Code review
  findings` for a code review. This write is the gate's flush. Then ask the
  user about them, one question per finding.
- **After the user responds**, move each decided finding to `### Handled` with
  the decision recorded:
  - *fixed as requested* - then implement it;
  - *rejected* - with the user's reason;
  - *question* - with its answer.
- **Findings the user ignored or skipped** (e.g. "go to the next phase" without
  addressing them) stay under `### Unhandled` as-is.

`### Unhandled` is the live list of open items. The plan must carry the
decisions the user took before the phase completes.

## Example

**Applied fixes**

- [src/auth.ts:42](src/auth.ts:42) - fixed token-expiry unit mismatch (s vs ms). `a1b2c3d`

---

**Findings** (Decision needed)

### 🟠 Q1 - A signed-in user gets logged out mid-checkout

**Issue.** Sessions only refresh when a page is read, not when a form is
submitted. Someone spends fifteen minutes filling in checkout, hits Pay, and
lands on the login screen with an empty cart. Does time spent in a form count
as being active?

**Why it's not already fixed.** It changes when every route on the site extends
a session, not just checkout, so it is a product call rather than a bug fix.

**Options.**

- **(a) Refresh on submit.** Any submit extends the session. The common case stops happening and nothing else changes.
- **(b) Warn first.** A banner at thirteen minutes with a "Keep me signed in" button. New UX surface to build, and it still loses the slowest users.
- **(c) Leave it.** Sessions stay read-only. Checkout keeps its drop-off.

**If we don't pick.** Slow checkouts keep failing silently. In the funnel it
reads as abandonment, so nobody goes looking for the bug.

<sub>Technical: [src/session.ts:88](src/session.ts:88) - `touch()` runs only in the `GET` middleware. Source: official-anthropic-review-skill, codex.</sub>

---

### 🟡 Q2 - The same pricing rules live in two places

**Issue.** Discounts are worked out once on the server and again in the browser
so the cart can update without waiting. Every future pricing change - a new
tier, a promo, a regional rule - has to be written twice. Miss one and the
customer sees one price and is charged another. Do we pay to keep them in sync,
or pay to merge them?

**Why it's not already fixed.** Any of the three answers changes the API
contract or the build, so none of them is the agent's to pick.

**Options.**

- **(a) One source on the server.** The cart asks for a fresh price on every change. One place to edit pricing forever, at the cost of a round trip and a visible lag on slow connections.
- **(b) Send the rules down.** The server ships the rule set as data and both sides read it. Keeps the instant cart, adds a versioned payload to the API contract.
- **(c) Leave it, with a tripwire.** Accept the duplication. Add a shared fixture that fails the build when the two disagree.

**If we don't pick.** The next pricing change is the one that ships a
mismatched price, and we hear about it from a customer.

<sub>Technical: [src/pricing.ts:120](src/pricing.ts:120) and [web/cart.ts:64](web/cart.ts:64). Source: ponytail.</sub>

---

**Quick read.** Q1 is a correctness call on a promise we already make to users
and wants an answer. Q2 is a how-much-machinery call - the cheapest option (c)
buys most of the safety.
