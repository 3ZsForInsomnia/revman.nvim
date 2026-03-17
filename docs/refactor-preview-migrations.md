# Revman Preview & Migrations Refactor Plan

Status: Proposal for implementation (to be followed by another chat). This document encodes the agreed constraints and exact changes to make.

Goals

- Centralize preview rendering in a picker-agnostic module that emits canonical markdown for all previewable entities (PRs, authors, notes).
- Keep existing picker usage and configuration unchanged for users.
- Split migrations into simple, named scripts under a migrations folder; expose a `:RevmanMigrate` command that lets the user run a single chosen migration against all PRs.
- Add PR `additions` and `deletions` (integers) via migration and sync. Backfill counts for existing PRs via a migration using existing GitHub data requests.
- Make highlights reusable across pickers (no Snacks-specific definitions).

Explicit constraints

- Previews:
  - Canonical output: markdown text; agnostic to picker.
  - Keep existing preview layout/content "exactly as is" except for adding diff summary (`Diff: +<additions> / -<deletions>` with colored icons) into the summary section.
  - Provide layered helper functions so users can build custom previews if desired.
  - Date formatting: use local time. Provide buckets: `n minutes/hours/days/weeks/months ago (2:35PM Mon, Jul 3, 2025)` — no ordinal suffixes (use Lua defaults for formatting).

- Migrations:
  - Use a simple folder of scripts: `lua/revman/db/migrations/` with numbered files (e.g., `001-...`, `002-...`, `003-...`).
  - No "run all" option. `:RevmanMigrate` uses `vim.ui.select` to choose and run a single migration.
  - Migrations run on all PRs.
  - Migration 003: add `additions` and `deletions` columns to `pull_requests` and backfill for all existing PRs using existing GitHub data requests.

- Sync:
  - Do not change the existing sync flows except to persist `additions`/`deletions` from the existing GitHub requests.
  - Provide an opt-in post-migration sync command (separate from repair) that users can run if desired.

- Commands:
  - Add `:RevmanMigrate` to pick and run one migration script.
  - Remove Snacks-specific commands if unused; rely on existing Revman commands and config for picker backend selection.

- Highlights:
  - Centralize highlight groups in a reusable module so both Telescope and Snacks adapters can consume them.

Planned module layout (no user-facing API changes)

- Preview (new folder; picker-agnostic)
  - `lua/revman/preview/format.lua`
    - `relative_with_absolute(iso_ts)` — local time buckets + absolute string
    - `format_status(text)` — snake_case to display (use existing rules)
    - `ci_icon(status)` — existing CI icon mapping
    - `diff_summary(additions, deletions)` — returns colored `Diff: +A / -D`
  - `lua/revman/preview/highlights.lua`
    - `setup()` — define highlight groups used in previews
  - `lua/revman/preview/pr.lua`
    - `render_markdown(pr)` — returns `{ text, ft = "markdown" }` with canonical layout; includes diff summary in status section
  - `lua/revman/preview/author.lua`
    - `render_markdown(author_stats)` — canonical author analytics preview
  - `lua/revman/preview/note.lua`
    - `render_markdown(note)` — markdown note content

- Picker adapters (internal refactor only; keep user config/usage the same)
  - Telescope PR/author/note previewers call into `preview/*.render_markdown` to populate buffer
  - Snacks items attach `item.preview = { text, ft }` from the same renderers

- Migrations (new folder and orchestrator)
  - `lua/revman/db/migrations/001-add-merged-fields.lua` — move existing logic out of schema
  - `lua/revman/db/migrations/002-populate-users-from-prs.lua` — move existing logic out of schema
  - `lua/revman/db/migrations/003-add-and-backfill-pr-diff-counts.lua`
    - `ALTER TABLE pull_requests ADD COLUMN additions INTEGER DEFAULT 0`
    - `ALTER TABLE pull_requests ADD COLUMN deletions INTEGER DEFAULT 0`
    - For all PRs, fetch existing data via current GitHub requests (no separate API call) and update counts
  - `lua/revman/db/migrations.lua`
    - Discovers available migrations, exposes `run(name)`; UI glue for `:RevmanMigrate`

- Commands
  - `:RevmanMigrate` — `vim.ui.select` to choose a single migration; applies to all PRs; logs results
  - Optional: `:RevmanSyncAllPRs` — opt-in resync to update newly added fields (only if needed; uses existing sync machinery)

- Schema
  - `lua/revman/db/schema.lua`: keep schema creation only; remove in-file migrations. Migrations live exclusively under `db/migrations/`.

Implementation notes

- Date bucketing rules:
  - minutes: <60 min → `N minutes ago (hh:MM AM/PM Wkday, Mon, D, YYYY)`
  - hours: <24 h → `N hours ago (...)`
  - days: <7 d → `N days ago (...)`
  - weeks: <5 w → `N weeks ago (...)`
  - months: <12 mo → `N months ago (...)`
  - years: otherwise → `N years ago (...)`
  - Use local time derived from `os.date` and Lua’s defaults for formatting; do not add ordinals.

- Diff summary:
  - Display string: `Diff: +<additions> / -<deletions>`
  - Coloring:
    - `+` and additions: green
    - `-` and deletions: red
  - Included in the summary/status block of PR preview

- Backfill migration (003):
  - Iterate all PRs in DB; for each, update `additions`/`deletions` using existing stored payloads or the existing sync fetch (no new request path introduced). If data not available, leave defaults and rely on opt-in resync.

- Snacks commands:
  - Verify they are unused in codebase; remove to avoid backend-specific command exposure.

Open confirmations (finalized by constraints provided)

- Timezone: local — confirmed.
- No ordinal suffixes — confirmed.
- No "run all migrations" option — confirmed.
- Use existing GitHub data requests — confirmed.
- Do not alter preview content beyond diff summary — confirmed.
- Only minimal sync change to persist additions/deletions — confirmed.

Next steps

- Another chat will implement the above refactor and features exactly as documented here, without changing user-facing picker configuration or usage.
