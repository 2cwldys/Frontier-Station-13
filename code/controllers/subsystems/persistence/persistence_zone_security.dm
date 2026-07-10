/*
 * Persistence - Z-Level Security Zones
 * EVE-style per-z security levels, DB-backed (ss13_zone_security):
 *   ZONE_NULLSEC (default) -- lawless; no announcements to admins, piracy unchecked
 *   ZONE_MEDSEC            -- factions enforce their own laws; normal attack logs only
 *   ZONE_HIGHSEC           -- Hub law; combat outlawed, harmful actions escalate to
 *                             admins (unconditional, with JMP) and feed the First
 *                             Responder program's offense list
 * Players get a large colored announcement when crossing INTO a different zone
 * level (same-zone deck changes stay silent). Zones show on the overmap as a
 * colored outline glow on each sector marker (placeholder visuals).
 * Managed by the "Set Z-Level Security Zone" admin verb.
 */

// ZONE_NULLSEC/ZONE_MEDSEC/ZONE_HIGHSEC are defined in
// code\__DEFINES\zone_security.dm (early compile for HUD/admin files)

/// Security zone per z-level, keyed "[z]" -> ZONE_* level. Absent = nullsec.
GLOBAL_LIST_EMPTY(zone_security_by_z)

/// Recent highsec offenses for the First Responder program: list of
/// list("name", "ref" (weakref), "x", "y", "z", "time"), newest last, capped.
GLOBAL_LIST_EMPTY(highsec_offense_log)

#define HIGHSEC_OFFENSE_LOG_MAX 20
#define OFFENSE_TRACK_COOLDOWN (10 MINUTES)

/// ckey -> world.time of their last TRACKED offense (log entry + PDA
/// alert). Does NOT gate the admin chat escalation, which fires every time.
GLOBAL_LIST_EMPTY(highsec_offense_last_tracked)

/// The security zone level of a z-level (ZONE_NULLSEC when unset).
/proc/zone_security_get(z)
	if(!z)
		return ZONE_NULLSEC
	var/level = GLOB.zone_security_by_z["[z]"]
	return isnull(level) ? ZONE_NULLSEC : level

/proc/zone_security_name(level)
	switch(level)
		if(ZONE_HIGHSEC) return "highsec"
		if(ZONE_MEDSEC)  return "medsec"
	return "nullsec"

/**
 * Load zone rows from the database into the in-memory map, then paint the
 * overmap markers. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/zoneSecurityInitialize()
	// MERGE into the existing map, never reassign -- pinned-site zones were
	// already registered during SSmapping init (build_pinned_away_sites),
	// before this proc runs
	if(!databaseCheckConnection("zoneSecurityInitialize"))
		return
	log_subsystem_persistence_info("Zone security: pinned_site_z=[GLOB.persistence_pinned_site_z ? english_list(GLOB.persistence_pinned_site_z) : "(empty)"] before ss13_zone_security load.")
	var/datum/db_query/zq = SSdbcore.NewQuery(
		"SELECT z, sec_level FROM ss13_zone_security", list())
	zq.Execute()
	var/loaded = 0
	if(databaseCheckQueryResult(zq, "zoneSecurityInitialize"))
		while(zq.NextRow())
			var/row_z = text2num(zq.item[1])
			var/row_level = text2num(zq.item[2])
			GLOB.zone_security_by_z["[row_z]"] = row_level
			log_subsystem_persistence_info("Zone security: loaded z=[row_z] -> [zone_security_name(row_level)] from ss13_zone_security.")
			loaded++
	qdel(zq)
	// Still paint the overmap even if the query above failed -- pinned-site
	// zones registered before this proc ran should still show correctly.
	zone_security_update_overmap()
	if(loaded)
		log_subsystem_persistence_info("Zone security: loaded [loaded] z-level zone(s). Final map: [json_encode(GLOB.zone_security_by_z)]")

/**
 * Paint every overmap sector marker with its zone's outline color
 * (placeholder visuals -- real sprite work later). Distress beacons keep
 * their own red outline (distress wins).
 */
/proc/zone_security_update_overmap()
	for(var/key in GLOB.map_sectors)
		var/obj/effect/overmap/visitable/marker = GLOB.map_sectors[key]
		if(!istype(marker) || marker.has_called_distress_beacon)
			continue
		var/marker_z = length(marker.map_z) ? marker.map_z[1] : 0
		switch(zone_security_get(marker_z))
			if(ZONE_HIGHSEC)
				marker.filters = filter(type = "outline", size = 1, color = "#54c556")
			if(ZONE_MEDSEC)
				marker.filters = filter(type = "outline", size = 1, color = "#e8bb4a")
			else
				marker.filters = null

/// Last zone level announced to this mob; -1 = never announced.
/// Tracking the LEVEL (not the z) makes announcements robust against
/// movement that never calls Moved() -- shuttles and lifts relocate mobs by
/// translating turfs underneath them, so a plain old-z/new-z comparison
/// misses those transitions permanently. With level tracking, the first
/// step after ANY missed transition self-corrects and announces.
/mob/var/zone_announce_level = -1

/// Announce when this mob's current zone level differs from the last one
/// announced. quiet_baseline suppresses the message and just records the
/// level (used at login so every fresh join doesn't print a banner).
/mob/proc/check_zone_announce(quiet_baseline = FALSE)
	if(!client)
		return
	// Pregame lobby mobs sit on a real station z but aren't "in" the world --
	// never announce (nor set the baseline; the spawned body announces fresh)
	if(istype(src, /mob/abstract/new_player))
		return
	var/nz = GET_Z(src)
	if(!nz)
		return
	var/new_level = zone_security_get(nz)
	if(new_level == zone_announce_level)
		return
	zone_announce_level = new_level
	if(quiet_baseline && new_level == ZONE_NULLSEC)
		return
	switch(new_level)
		if(ZONE_HIGHSEC)
			to_chat(src, FONT_LARGE(SPAN_COLOR("#54c556", "You are entering a highsec area! Piracy and combat is outlawed, Hub law is enforced.")))
		if(ZONE_MEDSEC)
			to_chat(src, FONT_LARGE(SPAN_COLOR("#e8bb4a", "You are entering a medsec area! Piracy is outlawed, factions enforce their own laws.")))
		else
			to_chat(src, FONT_LARGE(SPAN_COLOR("#e04545", "You are entering a nullsec area! Hub and faction laws are not enforced here.")))

/mob/Moved(atom/old_loc, movement_dir, forced, list/old_locs)
	. = ..()
	check_zone_announce()
// Login-time baseline call lives in /mob/Login() (code\modules\mob\login.dm)

/**
 * TRUE for Hub-faction members carrying security access -- they ARE the law
 * in highsec: their harmful actions bypass the combat restriction (no
 * HIGHSEC OFFENSE escalation, no responder alerts).
 */
/proc/zone_security_exempt(mob/M)
	if(!M || !ishuman(M) || !M.ckey)
		return FALSE
	var/mob/living/carbon/human/H = M
	var/obj/item/card/id/I = H.GetIdCard()
	if(!I || !(ACCESS_SECURITY in I.access))
		return FALSE
	if(!get_faction_member(H.ckey, "hub"))
		return FALSE
	return TRUE

/**
 * Record a highsec offense (called from admin_attack_log()): escalates to
 * every admin unconditionally (bypasses the CHAT_ATTACKLOGS preference) with
 * a JMP link every time, and feeds the First Responder offense list --
 * subject to a per-attacker cooldown so a single fight doesn't spam the
 * offense log/PDA alerts with one entry per hit.
 */
/proc/zone_security_record_offense(mob/attacker, mob/victim, admin_message)
	var/mob/anchor = victim || attacker
	if(!anchor)
		return
	message_admins("<span class='danger'>HIGHSEC OFFENSE:</span> [key_name(attacker)] against [key_name(victim)] -- [admin_message] (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[anchor.x];Y=[anchor.y];Z=[anchor.z]'>JMP</a>)")
	if(attacker)
		var/ck = attacker.ckey
		var/last_tracked = ck ? GLOB.highsec_offense_last_tracked[ck] : null
		if(ck && last_tracked && (world.time - last_tracked) < OFFENSE_TRACK_COOLDOWN)
			return // still on cooldown -- admin chat above already fired
		if(ck)
			GLOB.highsec_offense_last_tracked[ck] = world.time
		GLOB.highsec_offense_log += list(list(
			"name" = attacker.name,
			"ref"  = WEAKREF(attacker),
			"x"    = anchor.x,
			"y"    = anchor.y,
			"z"    = anchor.z,
			"time" = world.time
		))
		if(length(GLOB.highsec_offense_log) > HIGHSEC_OFFENSE_LOG_MAX)
			GLOB.highsec_offense_log.Cut(1, 2)
		zone_security_alert_responders(attacker, anchor)

/// ckey -> world.time of their last distress call. Separate from the offense
/// tracking map so a distress can't be swallowed by an unrelated offense cooldown.
GLOBAL_LIST_EMPTY(hub_distress_last_called)
#define DISTRESS_CALL_COOLDOWN (30 MINUTES)

/**
 * Civilian distress call: reports the caller's location to Hub security as a
 * First Responder offense-log entry (so responders can jump straight to
 * them, and their PDAs beep exactly like a normal offense), gated to highsec
 * zones only -- Hub law doesn't reach medsec/nullsec. Per-ckey cooldown,
 * separate from the offense-tracking cooldown above. Admin chat gets the
 * same unconditional JMP-linked escalation a normal offense does.
 */
/proc/zone_security_record_distress(mob/caller)
	if(!caller || !caller.ckey)
		return FALSE
	// Hub law only applies in highsec -- no distress line to Hub police from
	// medsec (factions enforce their own laws) or nullsec (no laws at all).
	if(zone_security_get(caller.z) != ZONE_HIGHSEC)
		return FALSE
	var/last = GLOB.hub_distress_last_called[caller.ckey]
	if(last && (world.time - last) < DISTRESS_CALL_COOLDOWN)
		return FALSE
	GLOB.hub_distress_last_called[caller.ckey] = world.time
	var/area/A = get_area(caller)
	message_admins("<span class='danger'>DISTRESS CALL:</span> [key_name(caller)] requests Hub security in [A ? A.name : "unknown location"] (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[caller.x];Y=[caller.y];Z=[caller.z]'>JMP</a>)")
	log_game("[key_name(caller)] sent a First Responder distress call at ([caller.x],[caller.y],[caller.z]).")
	GLOB.highsec_offense_log += list(list(
		"name" = "[caller.name] (distress call)",
		"ref"  = WEAKREF(caller),
		"x"    = caller.x,
		"y"    = caller.y,
		"z"    = caller.z,
		"time" = world.time
	))
	if(length(GLOB.highsec_offense_log) > HIGHSEC_OFFENSE_LOG_MAX)
		GLOB.highsec_offense_log.Cut(1, 2)
	// Same PDA-beep alert path a normal offense uses (zone_security_alert_responders below).
	zone_security_alert_responders(caller, caller, "DISTRESS CALL: [caller.name] requests Hub security in [A ? A.name : "unknown location"]! Open First Responder to respond.")
	return TRUE

/**
 * Beep every Hub-network computer/PDA carrying the First Responder program --
 * PDA-message-style alert: chat line with the device icon plus an audible
 * twobeep (get_notification handles the silent toggle). alert_text defaults
 * to the standard HIGHSEC OFFENSE wording; distress calls pass their own.
 */
/proc/zone_security_alert_responders(mob/attacker, mob/anchor, alert_text)
	var/area/offense_area = get_area(anchor)
	if(!alert_text)
		alert_text = "HIGHSEC OFFENSE: [attacker ? attacker.name : "unknown"] in [offense_area ? offense_area.name : "unknown location"]! Open First Responder to respond."
	for(var/obj/item/modular_computer/MC in world)
		// get_turf pierces nested containers -- a PDA in a pocket/backpack
		// must still receive the alert
		if(!get_turf(MC))
			continue
		if(normalize_faction_uid(MC.persistent_network) != "hub")
			continue
		// A dead-battery/powered-off PDA can't display the alert -- computer_use_power()
		// with its default zero-usage argument is a read-only power check, it doesn't
		// additionally drain the computer just to test this.
		if(!MC.enabled || !MC.screen_on || !MC.computer_use_power())
			continue
		if(!MC.hard_drive || !MC.hard_drive.find_file_by_name("firstresponder"))
			continue
		MC.get_notification(alert_text, 1, "First Responder")
		CHECK_TICK

/**
 * Find a security telepad for the given faction network.
 * Priority: faction telepad -> public telepad -> null.
 * Mirrors persistence_find_cargo_telepad().
 */
/proc/persistence_find_security_telepad(network = null)
	network = normalize_faction_uid(network)
	if(network)
		for(var/obj/structure/machinery/telepad_security/pad in world)
			if(!pad.z) continue
			if(!pad.persistent_spawn) continue
			if(normalize_faction_uid(pad.persistent_network) == network)
				return get_turf(pad)
	for(var/obj/structure/machinery/telepad_security/pad in world)
		if(!pad.z) continue
		if(lowertext(pad.persistent_network) == "public" && pad.persistent_spawn)
			return get_turf(pad)
	return null

/// Admin verb: jump your aghost onto the overmap chart to inspect sector
/// markers (zone outlines, pinned-site names/icons) in action.
/datum/admins/proc/view_overmap()
	set name = "View Overmap"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return
	if(!SSatlas.current_map.overmap_z)
		to_chat(usr, SPAN_WARNING("This map has no overmap."))
		return
	if(!isobserver(usr))
		to_chat(usr, SPAN_WARNING("Aghost first -- View Overmap moves your ghost onto the overmap chart."))
		return
	var/center = max(1, round(SSatlas.current_map.overmap_size / 2))
	var/turf/dest = locate(center, center, SSatlas.current_map.overmap_z)
	if(!dest)
		to_chat(usr, SPAN_WARNING("Could not locate the overmap chart."))
		return
	usr.forceMove(dest)
	to_chat(usr, SPAN_GOOD("Now viewing the overmap (z=[SSatlas.current_map.overmap_z]). Fly around to inspect sector markers, zone outlines, and pinned-site appearance."))

/// Admin verb: set a z-level's security zone, stored to DB immediately.
/datum/admins/proc/set_zone_security()
	set name = "Set Z-Level Security Zone"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(!SSpersistence.databaseCheckConnection("set_zone_security"))
		to_chat(usr, SPAN_WARNING("DB connection failed."))
		return

	// Status display with z identity labels
	var/msg = "Z-Level Security Zones (default: nullsec):\n"
	for(var/z = 1 to world.maxz)
		var/identity = ""
		var/obj/effect/overmap/visitable/z_sector = GLOB.map_sectors["[z]"]
		if(is_centcom_level(z))
			identity = " -- CentCom/admin"
		else if(SSmapping.level_trait(z, ZTRAIT_OVERMAP))
			identity = " -- Overmap chart"
		else if(is_station_level(z))
			identity = " -- station deck[z_sector ? " ([z_sector.name])" : ""]"
		else if(z_sector)
			identity = " -- [z_sector.name]"
		var/here = (z == usr.z) ? " <- you are here" : ""
		msg += "  Z=[z]: [uppertext(zone_security_name(zone_security_get(z)))][identity][here]\n"
	to_chat(usr, SPAN_NOTICE(msg))

	// "This Z-level" one-click path, or choose by number
	var/z_pick
	if(usr.z >= 1 && usr.z <= world.maxz)
		var/where_pick = tgui_input_list(usr, "Apply to which z-level?", "Set Z-Level Security Zone", list("This Z-level (Z=[usr.z])", "Choose Z-level"))
		if(!where_pick)
			return
		if(where_pick == "This Z-level (Z=[usr.z])")
			z_pick = usr.z
	if(isnull(z_pick))
		z_pick = tgui_input_number(usr, "Which z-level to change?", "Set Z-Level Security Zone", usr.z, world.maxz, 1)
	if(isnull(z_pick) || z_pick < 1 || z_pick > world.maxz)
		return

	var/list/level_choices = list("highsec" = ZONE_HIGHSEC, "medsec" = ZONE_MEDSEC, "nullsec" = ZONE_NULLSEC)
	var/level_pick = tgui_input_list(usr, "Security zone for Z=[z_pick] (currently [zone_security_name(zone_security_get(z_pick))]):", "Set Z-Level Security Zone", level_choices)
	if(!level_pick)
		return
	var/new_level = level_choices[level_pick]

	var/where_stored = persistence_set_zone_security(z_pick, new_level)

	switch(where_stored)
		if("pinned")
			to_chat(usr, SPAN_GOOD("Z=[z_pick] is now [uppertext(level_pick)]. Stored on the pinned site -- the zone follows it across reboots."))
			log_and_message_admins("set pinned-site z-level [z_pick] security zone to [level_pick]", usr)
		if("dynamic")
			to_chat(usr, SPAN_GOOD("Z=[z_pick] is now [uppertext(level_pick)] for THIS SESSION ONLY -- dynamic sites reshuffle each boot. Pin the site (Persistent Overmap Sites) to make its zone permanent."))
			log_and_message_admins("set dynamic-site z-level [z_pick] security zone to [level_pick] (session only)", usr)
		else
			to_chat(usr, SPAN_GOOD("Z=[z_pick] is now [uppertext(level_pick)]. Stored to DB; overmap updated."))
			log_and_message_admins("set z-level [z_pick] security zone to [level_pick]", usr)

/**
 * Sets a z-level's security zone in whatever storage is correct for that z
 * (pinned site row, session-only for dynamic/away sites, or the plain
 * ss13_zone_security table), updates the in-memory map, and repaints the
 * overmap. Returns "pinned", "dynamic", or "normal" so callers can message
 * appropriately. Shared by the admin verb above and the faction beacon's
 * claim/destruction hooks.
 */
/proc/persistence_set_zone_security(z, new_level)
	// Where the zone is stored depends on what the z IS. Away-site z-numbers
	// reshuffle each boot, so a z-keyed row would leak onto whatever spawns
	// at that number next session.
	if(z in GLOB.persistence_pinned_site_z)
		// Pinned site: zone lives on the pin row and follows the site across boots
		var/datum/db_query/pin_q = SSdbcore.NewQuery(
			"UPDATE ss13_persistent_away_sites SET sec_zone = :lvl WHERE last_z = :z AND map_path = :mp",
			list("lvl" = new_level, "z" = z, "mp" = "[SSatlas.current_map.path]")
		)
		pin_q.Execute()
		SSpersistence.databaseCheckQueryResult(pin_q, "set_zone_security pinned")
		qdel(pin_q)
		GLOB.zone_security_by_z["[z]"] = new_level
		zone_security_update_overmap()
		return "pinned"
	if(is_away_level(z) || (z in GLOB.persistence_template_loaded_z))
		// Dynamic site: session-only, no DB row (would misapply next boot)
		GLOB.zone_security_by_z["[z]"] = new_level
		zone_security_update_overmap()
		return "dynamic"
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_zone_security (z, sec_level)
		VALUES (:z, :lvl)
		ON DUPLICATE KEY UPDATE sec_level = VALUES(sec_level)"},
		list("z" = z, "lvl" = new_level)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "set_zone_security")
	qdel(q)
	GLOB.zone_security_by_z["[z]"] = new_level
	zone_security_update_overmap()
	return "normal"
