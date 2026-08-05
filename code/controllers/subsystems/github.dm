/**
 * # SSgithub -- GitHub Integration
 *
 * Builds on the codebase's existing revision tracking (GLOB.revdata,
 * code/datums/helper_datums/getrev.dm, populated from .git/logs/HEAD at
 * boot) and GLOB.config.githuburl (existing "GITHUBURL" config key, already
 * used by /client/verb/showrevinfo() to link commits/test-merges) rather
 * than re-deriving either. This subsystem adds the piece that didn't exist:
 * when GITHUB_ENABLED is set, periodically polls the GitHub REST API for
 * pull request activity and announces new opens/merges/denials to the
 * server.
 *
 * An optional GITHUB_TOKEN (raises the unauthenticated 60 req/hr rate limit)
 * is read from .env at the repo root, not config.txt -- see .env.example.
 */
SUBSYSTEM_DEF(github)
	name = "GitHub"
	wait = 5 MINUTES
	var/enabled = FALSE
	/// "[pr number]" -> "open"|"merged"|"closed", used to detect state transitions between polls
	var/list/known_prs = list()
	/// Whether the first (silent, cache-seeding) poll after boot has completed
	var/initial_poll_done = FALSE
	/// Repo owner and name, parsed from GLOB.config.githuburl (e.g. "https://github.com/owner/repo")
	var/github_owner
	var/github_repo
	/// Optional GitHub personal access token, read from .env (GITHUB_TOKEN) at the repo root -- never stored in config.txt
	var/github_token

/datum/controller/subsystem/github/Initialize()
	_parse_repo_path()
	github_token = _read_env_var("GITHUB_TOKEN")
	enabled = GLOB.config.github_enabled && github_owner && github_repo

	return SS_INIT_SUCCESS

/datum/controller/subsystem/github/proc/_parse_repo_path()
	PRIVATE_PROC(TRUE)

	var/url = GLOB.config.githuburl
	if(!url)
		return

	var/marker = "github.com/"
	var/idx = findtext(url, marker)
	if(!idx)
		return

	var/path = copytext(url, idx + length(marker))
	while(length(path) && copytext(path, length(path)) == "/")
		path = copytext(path, 1, length(path) - 1)

	var/list/parts = splittext(path, "/")
	if(parts.len < 2)
		return

	github_owner = parts[1]
	github_repo = parts[2]

/**
 * Reads a KEY=value pair out of the .env file at the repo root. Returns null
 * if .env doesn't exist or the key isn't set -- .env is gitignored, unlike
 * config.txt, so this is where secrets like GITHUB_TOKEN belong.
 */
/datum/controller/subsystem/github/proc/_read_env_var(key)
	PRIVATE_PROC(TRUE)

	if(!fexists(".env"))
		return null

	for(var/line in splittext(rustg_file_read(".env"), "\n"))
		line = trim(line)
		if(!length(line) || copytext(line, 1, 2) == "#")
			continue
		var/pos = findtext(line, "=")
		if(!pos)
			continue
		if(trim(copytext(line, 1, pos)) != key)
			continue
		return trim(copytext(line, pos + 1))

	return null

/**
 * Returns the GitHub URL for the currently running commit (GLOB.revdata.revision,
 * already populated at boot), or null if the revision or GITHUBURL aren't available.
 */
/datum/controller/subsystem/github/proc/get_commit_url()
	if(!GLOB.revdata?.revision || !GLOB.config.githuburl)
		return null
	return "[GLOB.config.githuburl]/commit/[GLOB.revdata.revision]"

/datum/controller/subsystem/github/fire(resumed)
	if(!enabled)
		return
	poll_pull_requests()

/datum/controller/subsystem/github/proc/poll_pull_requests()
	var/url = "https://api.github.com/repos/[github_owner]/[github_repo]/pulls?state=all&sort=updated&direction=desc&per_page=30"
	if(GLOB.config.github_branch)
		url += "&base=[GLOB.config.github_branch]"
	var/list/headers = list(
		"User-Agent" = "[GLOB.game_version]-server",
		"Accept" = "application/vnd.github+json",
	)
	if(github_token)
		headers["Authorization"] = "Bearer [github_token]"

	SShttp.create_async_request(RUSTG_HTTP_METHOD_GET, url, "", headers, CALLBACK(src, PROC_REF(_on_prs_response)))

/datum/controller/subsystem/github/proc/_on_prs_response(datum/http_response/response)
	PRIVATE_PROC(TRUE)

	if(!response || response.errored || response.status_code != 200)
		return

	var/list/prs
	try
		prs = json_decode(response.body)
	catch
		return

	if(!islist(prs))
		return

	for(var/list/pr in prs)
		var/num = "[pr["number"]]"
		var/merged = pr["merged_at"] ? TRUE : FALSE
		var/new_state = (pr["state"] == "closed") ? (merged ? "merged" : "closed") : "open"
		var/old_state = known_prs[num]

		if(initial_poll_done)
			if(isnull(old_state) && new_state == "open")
				_announce_pr(pr, "opened")
			else if(old_state == "open" && new_state == "merged")
				_announce_pr(pr, "merged")
#ifdef FORCE_COMPILE_ON_MERGE
				_check_deployment_merge(pr)
#endif
			else if(old_state == "open" && new_state == "closed")
				_announce_pr(pr, "denied")

		known_prs[num] = new_state

	initial_poll_done = TRUE

/datum/controller/subsystem/github/proc/_announce_pr(list/pr, action)
	PRIVATE_PROC(TRUE)

	var/verb = "opened"
	if(action == "merged")
		verb = "merged"
	else if(action == "denied")
		verb = "closed without merging"

	var/line = "<a href='[pr["html_url"]]'>Pull request #[pr["number"]]: [pr["title"]]</a> was [verb] by [pr["user"]["login"]]."

	if(action == "merged")
		to_chat(world, SPAN_GOOD(line))
	else if(action == "denied")
		to_chat(world, SPAN_WARNING(line))
	else
		to_chat(world, SPAN_NOTICE(line))

/**
 * Only called when FORCE_COMPILE_ON_MERGE is defined. Triggers
 * trigger_deployment_sync() (code/modules/admin/verbs/deploy.dm) the moment
 * a merged PR's base branch matches the configured deployment branch
 * (GLOB.config.github_branch) -- server-initiated, so triggered_by is null.
 */
/datum/controller/subsystem/github/proc/_check_deployment_merge(list/pr)
	PRIVATE_PROC(TRUE)

	if(!GLOB.config.github_branch)
		return

	var/base_ref = pr["base"] ? pr["base"]["ref"] : null
	if(base_ref != GLOB.config.github_branch)
		return

	trigger_deployment_sync(null)
