# Deployment

`scripts/deploy.sh` (Linux) / `scripts/deploy.ps1` (Windows) pull a
"deployment" branch and recompile so a fresh build is ready by the next
server restart.

Both do the same thing: `git fetch` + `git checkout -B <branch> origin/<branch>`
against `$DEPLOY_BRANCH`/`$env:DEPLOY_BRANCH` (defaults to `deployment`),
then recompile via `tools/build/build.sh` (Linux) or the same
`javascript.bat tools/build/build.ts` call `scripts/debug-compile.ps1` uses
(Windows) -- a real full build (tgui bundle + an actual DreamMaker compile),
not a stub. A successful compile's commit hash is written to
`scripts/.last-deployed-commit`, so a re-run with nothing new to pull is a
no-op, and a failed compile is retried on the next run instead of being
silently skipped forever.

**Neither script restarts DreamDaemon.** A fresh compile only goes live
once DreamDaemon is restarted -- that's still a separate step (manual, or
your own process supervisor/cron).

Run manually, or on a schedule, e.g.:
```
*/10 * * * * cd /path/to/repo && DEPLOY_BRANCH=deployment scripts/deploy.sh
```

## Triggering it from in-game

`R_SERVER` admins have a "Sync Deployment Branch" verb (Server category)
that runs the same script, backgrounded, without freezing the server:
`world.shelleo()` (the only way DM can shell out) blocks the whole game
world for as long as the shelled command takes, so the verb calls a tiny
wrapper (`scripts/deploy_bg.sh` / `deploy_bg.bat`) that launches
`deploy.sh`/`deploy.ps1` detached and returns immediately -- the actual
compile then runs in the background, logged to `scripts/deploy.log`.

It immediately broadcasts to everyone, in large text, "An admin is compiling
up to the latest commit on the deployment branch, effective next boot."
(anonymous to players; the triggering admin is still recorded via
`log_and_message_admins()` for the admin log). Since the compile itself
runs detached, a second background watcher then polls `scripts/deploy.log`
every 5 seconds (up to a 10-minute timeout) for that same run's outcome --
once it actually finishes, everyone gets a second broadcast, "Deployment
sync complete." in large green text. A failed compile is reported to
admins only (`message_admins()`), not broadcast world-wide.

It's safe to run again any time a newer merge lands -- the marker-file
check means it only actually recompiles when there's something new.

## Manual vs. automatic

By default, a sync only ever happens when an `R_SERVER` admin runs the verb
above. To have the server trigger it *itself* the moment a PR merges into
the deployment branch (no admin action needed), uncomment
`FORCE_COMPILE_ON_MERGE` in `code/_compile_options.dm`. With that defined,
`SSgithub` (which already polls the GitHub API for PR activity -- see
`GITHUB_ENABLED`/`GITHUBURL`/`GITHUB_BRANCH` in `config.txt`) calls the
exact same `trigger_deployment_sync()` the verb calls whenever it sees a
PR's base branch match `GITHUB_BRANCH` and its state flip to merged. The
only difference from a manual run is the wording of the broadcast ("A merge
to the deployment branch was detected -- compiling automatically..."
instead of "An admin is compiling...") and that failures go to
`message_admins()` instead of the triggering admin's chat, since there
isn't one. Leave it undefined (the default) to require the verb.
