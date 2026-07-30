# Aurora-Persistence -- Claude Code guidance

## Build verification (mandatory)

Verify EVERY change set with the AI-assisted build loop before handing back:

```
scripts/debug-compile.ps1 -ReportOnly    # in-session: prints error summary, you fix them
scripts/debug-compile.ps1                # standalone: self-fixes via headless claude, loops until clean
```

- Ends with a `===== DEBUG-COMPILE SUMMARY =====` block: `RESULT: CLEAN` or deduplicated `file:line:error` lines. Exit 0 = clean.
- Full log: `scripts/debug-compile.log`
- Wraps the Juke chain (`tools/build/build.bat` minus its interactive `pause`). tgui bundles rebuild automatically when `tgui/packages/**` changes; DM compiles when `code/**` or maps change.

## SQL migrations (mandatory)

Whenever a change set **adds a new `SQL/migrate-2023/V*.sql` file, or edits an existing one**, apply it before handing back:

```
scripts/db_update.ps1
```

- Re-runs every `V*.sql` in order against the `aurora-db` container. Already-applied migrations are skipped silently (`mariadb --force`), so it is **idempotent and safe to run at any time** -- re-running after a no-op change costs nothing.
- Ends with `Done. N file(s) processed, N hard error(s).` A non-zero hard-error count means a connection failure (check the `aurora-db` container is running), not a bad migration.
- Writing the migration file alone changes nothing at runtime: the new table/column simply won't exist, and the DM code reading it fails silently at runtime rather than at compile time -- `debug-compile.ps1` will still report `RESULT: CLEAN`. Nothing will tell you the step was skipped.
- Migrations are numbered sequentially (`V132__personal_cargo_category.sql`); check the highest existing `V*` number before naming a new one.

## Persistence debugging

Persistence subsystem activity (init steps, save/restore errors, panics) logs to
`data/logs/<round_id>/subsystems/persistence.log` -- a new file each round, so check
the most recently modified `data/logs/*/subsystems/` folder. Every init/finalize
step in `code/controllers/subsystems/persistence/persistence.dm` logs a
"Starting X..." line before it runs and catches+logs its own exceptions
(`log_subsystem_persistence_panic`), so a stuck or failed persistence step is
visible by scanning for the last "Starting..." line with no following step.

When diagnosing a reported persistence bug (state not saving/restoring,
a machine losing its config across a restart, etc.), check this log first
before reading code -- it often narrows down which subsystem step is
actually responsible.

## New admin verb checklist (mandatory)

Adding or editing ANY `/datum/admins/proc/` or `/client/proc/` admin verb is not done after writing the proc. It compiles clean either way, so a skipped step here produces no error -- the verb just silently never appears in the admin panel/right-click menu, and nothing will tell you that.

Before considering an admin verb finished:

1. `set name = "..."` and `set category = "..."` on the proc itself only control its label and which tab it's grouped under -- they do **not** grant the verb to anyone.
2. Grep `code/modules/admin/admin_verbs.dm` for the new proc's typepath (or an existing sibling verb defined in the same block). It must appear inside one of the `GLOBAL_LIST_INIT(admin_verbs_*, list(...))` blocks in that file -- that list is what `add_verb()` actually grants based on rights (`admin_verbs_admin` for `R_ADMIN`, `admin_verbs_server` for `R_SERVER`, etc., wired near the bottom of the file).
3. Match the list to the proc's own internal rights check (e.g. a proc gated on `check_rights(R_ADMIN)` belongs in `admin_verbs_admin`, not `admin_verbs_server` -- putting it in the wrong list either hides it from the people who should have it or grants it to people who shouldn't).
4. If it's missing, add it before calling the verb done -- do not report an admin-verb task as complete without having done this grep-and-check step.

## Hard rules for .dm files

- **ASCII only.** No em dashes, no Unicode of any kind -- the BYOND compiler breaks on it. Use `--` instead of an em dash.
- Never use `length(S.contents)` on arbitrary structures; beware BYOND var scoping pitfalls.
- `set waitfor = FALSE` procs fail silently -- audit call chains when porting code from other codebases.

## Project shape

- BYOND 516 codebase (aurorastation.dme), heavily modified for a persistent world: SQL-backed persistence subsystem in `code/controllers/subsystems/persistence/` (turfs, objects, worldstate, economy, atmos zones, mob inventory/health/identity).
- Subsystem init order matters: SSpersistence (INIT_ORDER_PERSISTENCE = -10) initializes AFTER SSair (-1) and after away-site templates load. Check `code/__DEFINES/subsystems.dm` before reasoning about init-time interactions.
- tgui is rspack-built (`bun tgui:build` inside tgui/), targeting Chromium WebView2 (`edge >= 123`). Binary assets referenced from shared SCSS should be inlined (`asset/inline`) -- runtime `url()` file references do not resolve in BYOND's browser cache.
- Players spawn through `PersistentAutoSpawn()` (`code/modules/mob/abstract/new_player/new_player.dm`), NOT the normal SSjobs round-start flow -- job-path-only setup (accounts, imprints) must be mirrored there.
