/*
 * Faction (recruitment)
 * Lets a player join a currently-recruiting faction at character creation
 * only -- the pick is consumed exactly once, the first time this character
 * slot actually spawns (new_player.dm, gated on the same is_first_ever_spawn
 * flag the starter PDA grant already uses), then it's inert for the rest of
 * that character's life. Deliberately not the same var as the legacy
 * `faction` pref (Occupation's old, now-hidden picker, and General's
 * species-switch handler both still touch that one) -- see faction_to_join's
 * own doc comment on /datum/preferences (preferences.dm).
 *
 * Picking a faction also offers a second list of that faction's specific
 * recruitable jobs (ss13_faction_jobs.recruitable, toggled per-job in the
 * Faction Management program/the "Manage Faction Jobs" admin verb) -- jobs
 * are the real unit of recruitment; picking none (or none being open) still
 * joins as a generic Civilian, same as before this existed.
 *
 * Rendered as plain classic-HTML link lists rather than tgui_input_list()
 * (a generic flat button-list popup with no per-item tooltip channel at
 * all, confirmed by reading its own ui_static_data()) specifically so a
 * plain HTML title="" attribute can give real native hover tooltips per
 * choice -- same convention origin.dm already uses elsewhere in this file
 * family, just without that file's need for a separate tgui_input_list-based
 * sub-menu.
 */

/datum/category_group/player_setup_category/faction_recruitment
	name = "Faction"
	sort_order = 2
	category_item_type = /datum/category_item/player_setup_item/faction_recruitment

/datum/category_item/player_setup_item/faction_recruitment
	name = "Faction"

/datum/category_item/player_setup_item/faction_recruitment/load_character(var/savefile/S)
	S["faction_to_join"] >> pref.faction_to_join
	S["faction_job_to_join"] >> pref.faction_job_to_join

/datum/category_item/player_setup_item/faction_recruitment/save_character(var/savefile/S)
	S["faction_to_join"] << pref.faction_to_join
	S["faction_job_to_join"] << pref.faction_job_to_join

/datum/category_item/player_setup_item/faction_recruitment/gather_load_query()
	return list(
		"ss13_characters" = list(
			"vars" = list("faction_to_join", "faction_job_to_join"),
			"args" = list("id")
		)
	)

/datum/category_item/player_setup_item/faction_recruitment/gather_load_parameters()
	return list("id" = pref.current_character)

/datum/category_item/player_setup_item/faction_recruitment/gather_save_query()
	return list(
		"ss13_characters" = list(
			"faction_to_join",
			"faction_job_to_join",
			"id" = 1,
			"ckey" = 1
		)
	)

/datum/category_item/player_setup_item/faction_recruitment/gather_save_parameters()
	return list(
		"faction_to_join" = pref.faction_to_join,
		"faction_job_to_join" = pref.faction_job_to_join,
		"id" = pref.current_character,
		"ckey" = PREF_CLIENT_CKEY
	)

/// Re-validated on every load, same defensive spirit as origin.dm's own
/// cascade -- a faction that stopped recruiting (or got deleted), or a job
/// that got un-marked recruitable (or renamed/removed), since this was
/// picked should never linger silently.
/datum/category_item/player_setup_item/faction_recruitment/sanitize_character(var/sql_load = 0)
	if(pref.faction_to_join && !get_faction_recruiting(pref.faction_to_join))
		pref.faction_to_join = null
	if(!pref.faction_to_join)
		pref.faction_job_to_join = null
		return
	if(pref.faction_job_to_join && !_job_still_recruitable(pref.faction_to_join, pref.faction_job_to_join))
		pref.faction_job_to_join = null

/// TRUE if `title` is still a job of `uid`'s AND still marked recruitable --
/// the same re-check both sanitize_character() above and the actual spawn
/// grant (new_player.dm) perform, so a job toggled off between chargen and
/// spawn never silently persists.
/datum/category_item/player_setup_item/faction_recruitment/proc/_job_still_recruitable(uid, title)
	for(var/list/j in get_faction_jobs(uid))
		if(j["title"] == title)
			return !!j["recruitable"]
	return FALSE

/// "FactionName (Company)" / "FactionName (Full Faction)" -- the same two
/// founding tiers a founding petition already picks between
/// (is_company_tier_faction(), persistence_factions.dm), matching the exact
/// wording founding/log messages already use.
/datum/category_item/player_setup_item/faction_recruitment/proc/_faction_label(uid)
	return "[get_faction_name(uid)] ([is_company_tier_faction(uid) ? "Company" : "Full Faction"])"

/// Hover text for a faction's own link -- whatever real, already-cached
/// info exists (its founding leader) rather than a "description" field that
/// nothing in this codebase actually ever sets today.
/datum/category_item/player_setup_item/faction_recruitment/proc/_faction_tooltip(uid)
	var/list/fc = GLOB.persistence_faction_cache[uid]
	var/leader = fc ? fc["leader_char_name"] : null
	return leader ? "Faction leader: [leader]" : "No faction leader on record."

/// Every faction currently open for chargen recruitment, "hub" excluded --
/// same "list every real faction" shape ui_data()'s known_factions and
/// give_faction_id()'s faction picker already use (persistence_factions.dm).
/datum/category_item/player_setup_item/faction_recruitment/proc/_recruiting_factions()
	var/list/uids = list()
	for(var/uid in GLOB.persistence_faction_cache)
		if(uid == "hub")
			continue
		if(!get_faction_recruiting(uid))
			continue
		uids += uid
	return uids

/// This faction's own recruitable jobs (ss13_faction_jobs.recruitable),
/// as {title -> job dict}, for building the second picker list.
/datum/category_item/player_setup_item/faction_recruitment/proc/_recruitable_jobs(uid)
	var/list/jobs = list()
	for(var/list/j in get_faction_jobs(uid))
		if(j["recruitable"])
			jobs[j["title"]] = j
	return jobs

/datum/category_item/player_setup_item/faction_recruitment/content(var/mob/user)
	var/list/dat = list()
	dat += "<br><br>"

	var/list/uids = _recruiting_factions()
	if(!length(uids))
		dat += "<i>No factions are currently recruiting.</i>"
		. = dat.Join()
		return

	var/none_selected = !pref.faction_to_join
	dat += (none_selected ? "<b>» " : "") + "<a href='byond://?src=[REF(src)];pick_faction=none' title='Skip joining a faction.'>Do not join a faction</a>" + (none_selected ? "</b>" : "") + "<br>"
	for(var/uid in uids)
		var/selected = (pref.faction_to_join == uid)
		dat += (selected ? "<b>» " : "") + "<a href='byond://?src=[REF(src)];pick_faction=[uid]' title='[_faction_tooltip(uid)]'>[_faction_label(uid)]</a>" + (selected ? "</b>" : "") + "<br>"

	if(pref.faction_to_join)
		dat += "<hr><b>Job with [get_faction_name(pref.faction_to_join)]:</b><br>"
		var/list/jobs = _recruitable_jobs(pref.faction_to_join)
		var/civ_selected = !pref.faction_job_to_join
		dat += (civ_selected ? "<b>» " : "") + "<a href='byond://?src=[REF(src)];pick_job=civilian' title='Join with no specific job -- a generic faction Civilian.'>General Member (Civilian)</a>" + (civ_selected ? "</b>" : "") + "<br>"
		for(var/title in jobs)
			var/list/j = jobs[title]
			var/job_selected = (pref.faction_job_to_join == title)
			var/tip = "Rank [j["rank"] || 0] -- [j["pay_rate"] || 0] cr/cycle"
			dat += (job_selected ? "<b>» " : "") + "<a href='byond://?src=[REF(src)];pick_job=[url_encode(title)]' title='[tip]'>[title]</a>" + (job_selected ? "</b>" : "") + "<br>"

	. = dat.Join()

/datum/category_item/player_setup_item/faction_recruitment/OnTopic(href, href_list, user)
	if(href_list["pick_faction"])
		if(!CanUseTopic(user))
			return TOPIC_NOACTION
		var/picked = href_list["pick_faction"]
		pref.faction_to_join = (picked == "none") ? null : picked
		pref.faction_job_to_join = null // a job choice only ever makes sense for the faction it came from
		sanitize_character()
		return TOPIC_REFRESH

	if(href_list["pick_job"])
		if(!CanUseTopic(user) || !pref.faction_to_join)
			return TOPIC_NOACTION
		var/picked_job = url_decode(href_list["pick_job"])
		pref.faction_job_to_join = (picked_job == "civilian") ? null : picked_job
		sanitize_character()
		return TOPIC_REFRESH
