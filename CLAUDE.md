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

## Hard rules for .dm files

- **ASCII only.** No em dashes, no Unicode of any kind -- the BYOND compiler breaks on it. Use `--` instead of an em dash.
- Never use `length(S.contents)` on arbitrary structures; beware BYOND var scoping pitfalls.
- `set waitfor = FALSE` procs fail silently -- audit call chains when porting code from other codebases.

## Project shape

- BYOND 516 codebase (aurorastation.dme), heavily modified for a persistent world: SQL-backed persistence subsystem in `code/controllers/subsystems/persistence/` (turfs, objects, worldstate, economy, atmos zones, mob inventory/health/identity).
- Subsystem init order matters: SSpersistence (INIT_ORDER_PERSISTENCE = -10) initializes AFTER SSair (-1) and after away-site templates load. Check `code/__DEFINES/subsystems.dm` before reasoning about init-time interactions.
- tgui is rspack-built (`bun tgui:build` inside tgui/), targeting Chromium WebView2 (`edge >= 123`). Binary assets referenced from shared SCSS should be inlined (`asset/inline`) -- runtime `url()` file references do not resolve in BYOND's browser cache.
- Players spawn through `PersistentAutoSpawn()` (`code/modules/mob/abstract/new_player/new_player.dm`), NOT the normal SSjobs round-start flow -- job-path-only setup (accounts, imprints) must be mirrored there.
