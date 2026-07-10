/*
 * Persistence - Cryo Logout System
 * When a player disconnects, their character enters "cryosleep":
 *   1. Position, health, and inventory are saved immediately.
 *   2. The mob stays in the world for PERSISTENCE_CRYO_TIMEOUT seconds.
 *   3. If the player reconnects within that window, the despawn is cancelled.
 *   4. If the timer expires, the mob is removed from the world.
 *   5. On reconnect after despawn, PersistentAutoSpawn() restores them at saved position.
 */

#define PERSISTENCE_CRYO_TIMEOUT (60 SECONDS)
#define PERSISTENCE_BASE_SLOTS   1
#define PERSISTENCE_ADMIN_SLOTS  3

// Cryo state vars on the human mob
/mob/living/carbon/human
	var/persistence_in_cryo      = FALSE
	var/persistence_cryo_timer   = null
	var/persistence_stored_ckey  = ""

/mob/living/carbon/human/proc/persistence_cryo_despawn()
	if(!persistence_in_cryo || ckey)
		return

	if(stat == DEAD)
		_persistence_dead_despawn()
		return

	// Find a hold turf  prefer player storage telepads, fall back to any latejoin point
	var/turf/hold_turf = null
	if(length(GLOB.player_storage_tepads))
		var/obj/structure/machinery/player_storage_telepad/pad = pick(GLOB.player_storage_tepads)
		hold_turf = get_turf(pad)
	else if(length(GLOB.latejoin))
		hold_turf = pick(GLOB.latejoin)

	if(hold_turf)
		log_subsystem_persistence_info("Cryo: [real_name] moved to offline hold at ([hold_turf.x],[hold_turf.y],[hold_turf.z]).")
		forceMove(hold_turf)
		stat         = UNCONSCIOUS
		density      = FALSE
		status_flags |= GODMODE  // Prevent hunger/thirst/health damage while stored
		// Stay in world until player reconnects (cleaned up in PersistentAutoSpawn)
	else
		log_subsystem_persistence_info("Cryo: [real_name] despawning  no offline hold configured.")
		qdel(src)

/**
 * A character who died and logged off (or timed out) before reaching cryo never
 * got their lace routed anywhere -- capture only happens at surgical extraction.
 * Extract now (works offline, the mind stays on the corpse per neural_lace.dm
 * removed()) and route it through the same faction/public priority the manual
 * 4-hour auto-transfer uses, then hold the corpse same as any dead body.
 */
/mob/living/carbon/human/proc/_persistence_dead_despawn()
	var/obj/item/organ/internal/neural_lace/lace = internal_organs_by_name["neural_lace"]
	if(istype(lace) && !QDELETED(lace))
		lace.removed(src, null, TRUE, TRUE)
		lace._auto_transfer_to_storage()
		log_subsystem_persistence_info("Cryo: [real_name] found dead offline -- neural lace extracted and routed to storage.")

	var/turf/hold_turf = null
	if(length(GLOB.player_storage_tepads))
		var/obj/structure/machinery/player_storage_telepad/pad = pick(GLOB.player_storage_tepads)
		hold_turf = get_turf(pad)
	else if(length(GLOB.latejoin))
		hold_turf = pick(GLOB.latejoin)

	if(hold_turf)
		log_subsystem_persistence_info("Cryo: [real_name]'s corpse moved to offline hold at ([hold_turf.x],[hold_turf.y],[hold_turf.z]).")
		forceMove(hold_turf)
		density      = FALSE
		status_flags |= GODMODE
		// stat stays DEAD -- do not resurrect. Reconnecting finds the corpse via PersistentAutoSpawn.
	else
		log_subsystem_persistence_info("Cryo: [real_name]'s corpse despawning  no offline hold configured.")
		qdel(src)

/**
 * Save the position of a disembodied consciousness at logout, keyed on the
 * lace's registered identity. Nothing else needs saving -- health/inventory/
 * identity belong to the body, not the consciousness, and the lace item
 * itself is persisted separately (installed as an organ, or via the vault).
 */
/datum/controller/subsystem/persistence/proc/_persistLaceMobOnLogout(mob/living/carbon/lace_mob/LM)
	if(!databaseCheckConnection("persistCharacterOnLogout lace"))
		return
	var/obj/item/organ/internal/neural_lace/lace = LM.neural_lace
	if(!lace || !lace.registered_ckey || !lace.registered_name)
		return
	var/turf/T = get_turf(lace) || get_turf(LM)
	if(!T)
		return
	lacePositionSave(lace.registered_ckey, lace.registered_name, T)
	log_subsystem_persistence_info("Cryo: [lace.registered_name] ([lace.registered_ckey]) lace-consciousness saved at logout.")

/**
 * Called from /client/Destroy() when a player disconnects.
 * Saves character state and starts the despawn countdown.
 */
/datum/controller/subsystem/persistence/proc/persistCharacterOnLogout(mob/living/L)
	if(!GLOB.config.sql_enabled)
		return
	if(!L || QDELETED(L))
		return
	if(istype(L, /mob/living/carbon/lace_mob))
		_persistLaceMobOnLogout(L)
		return
	if(!istype(L, /mob/living/carbon/human))
		return
	var/mob/living/carbon/human/H = L
	if(!H.ckey || !H.real_name)
		return
	// Use get_turf() rather than H.z directly  when H is inside a cryopod or other
	// container, H.z is 0 (not on a turf directly). get_turf() resolves through containers.
	var/turf/H_turf = get_turf(H)
	if(!H_turf || !H_turf.z)
		return

	if(!databaseCheckConnection("persistCharacterOnLogout"))
		return

	// Logging off INSIDE a cryopod = a forced Store Character: full DB store,
	// mob moved to the offline hold, pod freed, that pod remembered as theirs.
	// Reconnects go through the character menu instead of the 60s grace body.
	// This is the fast path when client/Destroy fires; the pod's process()
	// makes the same call within ~2s for disconnects that bypass it.
	if(istype(H.loc, /obj/structure/machinery/cryopod))
		var/obj/structure/machinery/cryopod/pod = H.loc
		if(pod.persistence_force_store(H))
			return
		// Force-store unavailable (DB down etc) -- fall through to the normal despawn flow.

	mobPositionSave(H)
	mobsHealthSaveOne(H)
	mobsInventorySaveOne(H)
	charIdentitySaveOne(H)

	H.persistence_stored_ckey = H.ckey
	H.persistence_in_cryo     = TRUE

	var/datum/callback/cryo_cb = new /datum/callback(H, TYPE_PROC_REF(/mob/living/carbon/human, persistence_cryo_despawn))
	H.persistence_cryo_timer = addtimer(cryo_cb, PERSISTENCE_CRYO_TIMEOUT, TIMER_STOPPABLE | TIMER_DELETE_ME)

	log_subsystem_persistence_info("Cryo: [H.real_name] ([H.ckey]) saved and entering cryosleep.")

/**
 * Intentional store: saves the character, immediately moves the mob to a player storage
 * telepad, and returns the client to the new_player lobby so they can Join again later.
 * Unlike persistCharacterOnLogout() this does NOT use a timer  storage is instant.
 */
/datum/controller/subsystem/persistence/proc/persistStoreCharacter(mob/living/carbon/human/H, obj/structure/machinery/cryopod/pod = null)
	if(!GLOB.config.sql_enabled)
		return FALSE
	if(!H || QDELETED(H))
		return FALSE
	if(!H.ckey || !H.real_name)
		return FALSE
	var/turf/H_turf = get_turf(H)
	if(!H_turf || !H_turf.z)
		return FALSE
	if(!databaseCheckConnection("persistStoreCharacter"))
		return FALSE

	// Save all character data
	mobPositionSave(H)
	mobsHealthSaveOne(H)
	mobsInventorySaveOne(H)
	charIdentitySaveOne(H)

	// Remember which pod they stored at so they wake from the same one --
	// after mobPositionSave so the row exists, before the ckey is cleared.
	if(pod)
		persistence_set_last_pod(H.ckey, H.real_name, pod)

	H.persistence_stored_ckey = H.ckey
	H.persistence_in_cryo     = TRUE

	// If the mob is inside a cryopod, clear its occupant reference so the pod resets properly
	if(istype(H.loc, /obj/structure/machinery/cryopod))
		var/obj/structure/machinery/cryopod/cryo_pod = H.loc
		if(cryo_pod.occupant == H)
			cryo_pod.occupant = null
			cryo_pod.update_icon()

	// Move mob immediately to the player storage telepad (or latejoin fallback)
	var/turf/hold_turf = null
	if(length(GLOB.player_storage_tepads))
		var/obj/structure/machinery/player_storage_telepad/pad = pick(GLOB.player_storage_tepads)
		hold_turf = get_turf(pad)
	else if(length(GLOB.latejoin))
		hold_turf = pick(GLOB.latejoin)

	if(hold_turf)
		H.forceMove(hold_turf)
		H.stat         = UNCONSCIOUS
		H.density      = FALSE
		H.status_flags |= GODMODE  // Prevent hunger/thirst/health damage while stored
		log_subsystem_persistence_info("Cryo: [H.real_name] stored at telepad ([hold_turf.x],[hold_turf.y],[hold_turf.z]).")
	else
		// No hold turf available -- the character save above already fully
		// completed, so it's safe to remove the mob outright, matching
		// persistence_cryo_despawn()/_persistence_dead_despawn()'s existing
		// pattern in this same file. Leaving it in place without GODMODE (the
		// success branch above applies stat/density/GODMODE together as one
		// unit) left a live, un-flagged mob sitting in the world that would
		// resume normal Life() ticking -- including the SSD auto-sleep path
		// re-triggering Sleeping() every few minutes -- forever.
		log_subsystem_persistence_info("Cryo: [H.real_name] stored  no telepad found, removing mob.")
		// Deferred, not immediate -- the calling verb (store_character()) still
		// needs to transfer H's attached client to a new lobby mob right after
		// this proc returns, with no sleep() in between. Deleting H synchronously
		// here would sever that in-flight handoff and strand the client instead
		// of returning it to the main menu.
		QDEL_IN(H, 0)
		return TRUE

	return TRUE

// ============================================================
// POST-CRYO CHILL EFFECT
// ============================================================

/// Visual phase of the chill effect: cyan-turquoise wash + cold border under
/// the HUD. No sound, no slowdown, no fade timer -- shown for as long as the
/// mob sits inside a cryopod (set_occupant applies it; the pod exit finishes
/// the effect via finish_cryo_chill).
/mob/living/carbon/human/proc/apply_cryo_chill_visuals()
	add_client_color(/datum/client_color/chilled)
	var/atom/movable/screen/fullscreen/chilled/border = overlay_fullscreen("chilled", /atom/movable/screen/fullscreen/chilled, null, 0.5 SECONDS)
	if(border && client)
		// Scale the 480x480 border up to the client's (dynamic) view so it
		// fills the whole screen -- transforms don't expand the viewport,
		// unlike an oversized icon.
		var/list/vs = getviewsize(client.view)
		var/scale = max(vs[1], vs[2]) * WORLD_ICON_SIZE / 480
		if(scale > 1)
			border.transform = matrix(scale, 0, 0, 0, scale, 0)

/// Exit phase: a chilled sound others can hear, ~15 seconds of sluggish
/// movement, and the 15-second countdown after which the visuals fade out.
/mob/living/carbon/human/proc/finish_cryo_chill()
	cryo_chill_pending = FALSE
	cryo_exited_at = world.time
	chilled_until = world.time + 15 SECONDS
	playsound(get_turf(src), 'sound/effects/chilled.ogg', 75, 1)
	addtimer(CALLBACK(src, PROC_REF(clear_cryo_chill)), 15 SECONDS, TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_DELETE_ME)

/// Both phases at once -- for wake paths that couldn't place the mob in a
/// pod (there is no exit moment to split the effect around).
/mob/living/carbon/human/proc/apply_cryo_chill()
	apply_cryo_chill_visuals()
	finish_cryo_chill()

/mob/living/carbon/human/proc/clear_cryo_chill()
	remove_client_color(/datum/client_color/chilled)  // animates back over 1 second
	clear_fullscreen("chilled", 1.5 SECONDS)          // alpha fade-out

// ============================================================
// ENTER CRYOSLEEP VERB  manual logout via cryopod
// ============================================================

// Deliberately a proc, not a verb -- removed from the Persistence tab; players
// enter pods physically (or code paths may call this directly).
/mob/living/carbon/human/proc/enter_cryosleep()

	if(!GLOB.config.sql_enabled)
		to_chat(src, SPAN_WARNING("Persistence is not enabled on this server."))
		return

	// Find the nearest cryopod within 3 tiles
	var/obj/structure/machinery/cryopod/nearest = null
	var/nearest_dist = 999
	for(var/obj/structure/machinery/cryopod/pod in range(3, src))
		if(pod.occupant)
			continue
		var/d = get_dist(src, pod)
		if(d < nearest_dist)
			nearest_dist = d
			nearest = pod

	if(!nearest)
		to_chat(src, SPAN_WARNING("No available cryopod nearby. Walk up to an empty cryopod and try again."))
		return

	// Check faction access on restricted pods
	if(nearest.persistent_network && nearest.persistent_network != "public")
		var/player_faction = persistence_get_player_faction(src.ckey)
		if(player_faction != nearest.persistent_network)
			to_chat(src, SPAN_WARNING("This cryopod is restricted to [nearest.persistent_network] personnel only."))
			return

	var/confirm = tgui_alert(src, "Enter cryosleep? Your character will be saved and you will be logged out.", "Enter Cryosleep", list("Enter", "Cancel"))
	if(confirm != "Enter")
		return

	// Move to the tile in front of the pod (visual effect only  not inside the pod)
	to_chat(src, SPAN_NOTICE("You climb into the cryopod and settle in for cryosleep..."))
	var/turf/pod_front = get_step(nearest, nearest.dir)
	if(!pod_front)
		pod_front = get_turf(nearest)
	src.forceMove(pod_front)

	// Save character and immediately move mob to player storage telepad
	if(!SSpersistence.persistStoreCharacter(src, nearest))
		to_chat(src, SPAN_WARNING("Storage failed  could not save character data. Please try again."))
		return

	// Return the client to the lobby (new_player) so they can Join again later.
	// We store the key first since detaching the client clears src.key.
	var/stored_key = src.key
	if(client)
		client.stop_ambient_playlist()  // Otherwise it keeps playing over the lobby music
	var/mob/abstract/new_player/NP = new /mob/abstract/new_player()
	NP.key = stored_key  // Transfers the client from src to NP; src.ckey becomes null

// ============================================================
// CLIENT HOOK  save on disconnect
// ============================================================

/client/Destroy(force)
	// Save this character before the client reference is cleared
	if(!gc_destroyed && mob)
		if(istype(mob, /mob/living/carbon/human))
			var/mob/living/carbon/human/H = mob
			if(H.ckey && H.real_name && !QDELETED(H))
				SSpersistence.persistCharacterOnLogout(H)
		else if(istype(mob, /mob/living/carbon/lace_mob) && !QDELETED(mob))
			SSpersistence.persistCharacterOnLogout(mob)
	stop_ambient_playlist()  // Cancel any pending timers before the client reference dies
	. = ..()

// ============================================================
// CRYOPOD NETWORK SYSTEM
// ============================================================

// New vars on cryopods for network/faction designation
/obj/structure/machinery/cryopod
	/// Network this pod belongs to. "public" = open to all. A faction UID restricts to that faction.
	/// Empty string = unconfigured (not a spawn point). Must be set explicitly via Configure Cryopod Network.
	var/persistent_network = ""
	/// If TRUE and persistent_network == "public", this pod is a valid spawn point.
	/// Defaults to FALSE -- must be explicitly enabled by an admin.
	var/persistent_spawn   = FALSE
	/// TRUE if this cryopod was placed on the original map (handled by worldstate). FALSE = admin-spawned (handled by persistent_objects).
	var/persistence_map_placed = FALSE
	/// Never expire spawned cryopods
	persistant_objects_expiration_time_days = 36500

// Faction assignment is configured via the faction tagger tool now (see
// faction_tagger_set() in persistence_faction_tagger.dm). This admin-only
// quick-access verb stays for a "raw" session where nobody has a faction ID
// yet, or for admins who don't want to dig out a tagger item.
/obj/structure/machinery/cryopod/verb/configure_faction_network()
	set name = "Configure Faction Network"
	set category = "Admin"
	set desc = "Force-set or clear this cryopod's faction network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	to_chat(usr, SPAN_NOTICE("Current network: [persistent_network ? persistent_network : "(none)"] | spawn=[persistent_spawn]"))

	var/new_network = tgui_input_text(usr, "Enter network ID (a faction UID, 'public', or leave blank to clear):", "Configure Faction Network", persistent_network, max_length = 32)
	if(new_network == null)
		return

	var/new_uid = new_network ? normalize_faction_uid(new_network) : null
	if(faction_tagger_set(new_uid, usr))
		to_chat(usr, SPAN_GOOD("Cryopod network set to: [persistent_network ? persistent_network : "(none)"][persistent_spawn ? " (spawn point)" : ""]"))
		log_admin("[key_name(usr)] force-configured cryopod at ([x],[y],[z]) network to '[persistent_network]' via admin verb.")

/obj/structure/machinery/cryopod/Initialize(mapload, ...)
	. = ..()
	if(mapload)
		persistence_map_placed = TRUE  // Map-placed: worldstate handles it

/// Spawned cryopods: save position + network config for re-creation on load
/obj/structure/machinery/cryopod/persistent_objects_get_content()
	return list(
		"persistent_network" = persistent_network,
		"persistent_spawn"   = persistent_spawn
	)

/// On load: if a map-placed cryopod already exists at this position, configure it and qdel self.
/// Otherwise move to saved position and configure.
/obj/structure/machinery/cryopod/persistent_objects_apply_content(list/content, x, y, z)
	// x/y/z come from SQL as strings  convert to numbers for locate()
	var/nx = text2num(x)
	var/ny = text2num(y)
	var/nz = text2num(z)
	if(nx && ny && nz)
		var/turf/target = locate(nx, ny, nz)
		if(target)
			// If any cryopod already exists here, configure it, transfer DB tracking to it,
			// then remove the duplicate. Transferring the track_id preserves the DB entry so
			// objectsFinalize updates rather than deletes it.
			for(var/obj/structure/machinery/cryopod/existing in target)
				if(existing == src)
					continue
				if(!isnull(content["persistent_network"]) && length(content["persistent_network"]))
					existing.persistent_network = content["persistent_network"]
				if(!isnull(content["persistent_spawn"]))
					existing.persistent_spawn = content["persistent_spawn"]
				// Hand off DB ownership so finalize updates this entry instead of purging it
				existing.persistent_objects_track_id = src.persistent_objects_track_id
				SSpersistence.objectsRegisterTrack(existing, src.persistent_objects_author_ckey)
				qdel(src)
				return
			forceMove(target)
	// Preserve type defaults ("public"/TRUE) if DB value is null or empty
	if(!isnull(content["persistent_network"]) && length(content["persistent_network"]))
		persistent_network = content["persistent_network"]
	if(!isnull(content["persistent_spawn"]))
		persistent_spawn = content["persistent_spawn"]

/**
 * Look up the primary faction UID for a player from the ss13_faction_members table.
 * Returns null if the player has no faction membership.
 */
/proc/persistence_get_player_faction(ckey)
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return null
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT faction_uid FROM ss13_faction_members WHERE ckey = :ckey LIMIT 1",
		list("ckey" = ckey)
	)
	var/faction_uid = null
	try
		q.Execute()
		if(q.NextRow())
			faction_uid = q.item[1]
	catch
		// Table may not exist yet  return null safely
	qdel(q)
	return faction_uid

/**
 * Find the cryopod this character last stored at (persistence_set_last_pod)
 * and return it, or null so the caller falls back to the normal spawn
 * cascade. Falls back when the pod is missing, occupied, unpowered/broken,
 * or its faction network no longer matches the player.
 */
/proc/persistence_find_saved_cryopod(ckey, char_name)
	if(!GLOB.config.sql_enabled || !ckey || !char_name)
		return null
	var/list/entry = GLOB.persistence_position_cache["[ckey]|[char_name]"]
	if(!islist(entry) || !entry["last_pod_z"])
		return null
	var/pz = entry["last_pod_z"]
	if(pz < 1 || pz > world.maxz)
		return null
	var/turf/T = locate(entry["last_pod_x"], entry["last_pod_y"], pz)
	var/obj/structure/machinery/cryopod/pod = T ? (locate(/obj/structure/machinery/cryopod) in T) : null
	if(!pod)
		return null
	if(pod.occupant)
		return null
	if(pod.stat & (NOPOWER|BROKEN))
		return null
	if(pod.persistent_network && pod.persistent_network != "public")
		var/player_faction = persistence_get_player_faction(ckey)
		if(normalize_faction_uid(player_faction) != normalize_faction_uid(pod.persistent_network))
			return null
	return pod

/**
 * Find an available cryopod using the priority cascade:
 *   1. Faction pod matching faction_uid (exclusive to that faction)
 *   2. Public or unrestricted pod (persistent_network = "public" or "", persistent_spawn = TRUE)
 * Returns the chosen POD, or null (callers handle landmark fallbacks).
 */
/proc/persistence_find_available_cryopod(faction_uid = null)
	// Priority 1: faction's own pods
	if(faction_uid)
		var/list/faction_pods = list()
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(!pod.z || pod.occupant || (pod.stat & (NOPOWER|BROKEN))) continue
			if(pod.persistent_network == faction_uid)
				faction_pods += pod
		if(length(faction_pods))
			return pick(faction_pods)

	// Priority 2: public or unrestricted spawn pods (open to everyone)
	// Accepts both persistent_network == "public" (explicitly public) and
	// persistent_network == "" (unrestricted  no faction restriction set)
	var/list/public_pods = list()
	var/total_pods = 0
	for(var/obj/structure/machinery/cryopod/pod in world)
		total_pods++
		if(!pod.z)
			log_subsystem_persistence_info("Cryo spawn: skipping [pod.type] at ([pod.x],[pod.y],[pod.z])  z is 0")
			continue
		if(pod.occupant)
			log_subsystem_persistence_info("Cryo spawn: skipping [pod.type] at ([pod.x],[pod.y],[pod.z])  occupied by [pod.occupant]")
			continue
		if(pod.stat & (NOPOWER|BROKEN))
			log_subsystem_persistence_info("Cryo spawn: skipping [pod.type] at ([pod.x],[pod.y],[pod.z])  unpowered/broken")
			continue
		var/is_open = (pod.persistent_network == "public")
		if(is_open && pod.persistent_spawn)
			public_pods += pod
		else
			log_subsystem_persistence_info("Cryo spawn: skipping [pod.type] at ([pod.x],[pod.y],[pod.z])  network='[pod.persistent_network]' spawn=[pod.persistent_spawn]")
	log_subsystem_persistence_info("Cryo spawn: checked [total_pods] pods, found [length(public_pods)] public/unrestricted.")
	if(length(public_pods))
		return pick(public_pods)
	return null

// ============================================================
// GHOST VERB BLOCK  prevent ghosting while in/near cryopod
// ============================================================

/// Override ghost verb on humans: block ghosting while inside a cryopod or already in cryo-storage.
/// Players should use the Store Character verb instead.
/mob/living/carbon/human/ghost()
	if(istype(loc, /obj/structure/machinery/cryopod) || persistence_in_cryo)
		to_chat(src, SPAN_WARNING("You cannot ghost while in cryosleep. Use the <b>Store Character</b> verb in the <b>Persistence</b> category to store your character properly."))
		return
	. = ..()

// ============================================================
// STORE CHARACTER VERB
// ============================================================

/// Store Character: saves the player's character and queues them for the offline hold area.
/// Requires the player to be inside or directly adjacent to a cryopod.
/mob/living/carbon/human/verb/store_character()
	set name = "Store Character"
	set category = "Persistence"
	set desc = "Save your character and go offline. Must be inside or next to a cryopod."

	if(!GLOB.config.sql_enabled)
		to_chat(src, SPAN_WARNING("Persistence is not enabled on this server."))
		return

	if(persistence_in_cryo)
		to_chat(src, SPAN_WARNING("Your character is already being stored."))
		return

	// Must be inside a cryopod or standing directly adjacent to one
	var/obj/structure/machinery/cryopod/near_pod = null
	if(istype(loc, /obj/structure/machinery/cryopod))
		near_pod = loc
	else
		for(var/obj/structure/machinery/cryopod/pod in range(1, src))
			near_pod = pod
			break
	if(!near_pod)
		to_chat(src, SPAN_WARNING("You must be inside or adjacent to a cryopod to store your character."))
		return

	// Faction-owned pods only serve their own members
	if(near_pod.persistent_network && near_pod.persistent_network != "public")
		var/player_faction = persistence_get_player_faction(src.ckey)
		if(normalize_faction_uid(player_faction) != normalize_faction_uid(near_pod.persistent_network))
			to_chat(src, SPAN_WARNING("This cryopod is restricted to [near_pod.persistent_network] personnel only."))
			return

	var/confirm = tgui_alert(src, "Store your character and go offline? Your character will be saved and moved to a safe holding area until you reconnect.", "Store Character", list("Store", "Cancel"))
	if(confirm != "Store")
		return

	// Save character and immediately move mob to player storage telepad
	if(!SSpersistence.persistStoreCharacter(src, near_pod))
		to_chat(src, SPAN_WARNING("Storage failed  could not save character data. Please try again."))
		return

	to_chat(src, SPAN_NOTICE("Character stored. You will return to the main menu now  click Join to come back."))

	// Return the client to the lobby (new_player) so they can Join again later.
	var/stored_key = src.key
	if(client)
		client.stop_ambient_playlist()  // Otherwise it keeps playing over the lobby music
	var/mob/abstract/new_player/NP = new /mob/abstract/new_player()
	NP.key = stored_key  // Transfers the client from src to NP; src.ckey becomes null

// ============================================================
// CHARACTER LIST HELPER
// ============================================================

/**
 * Returns a list of character names (strings) that have saved data for a given ckey.
 * Scans the in-memory caches loaded at startup  no DB call needed.
 */
/proc/persistence_get_saved_characters(ckey)
	var/list/chars = list()
	var/prefix = "[ckey]|"
	var/plen = length(prefix)

	if(islist(GLOB.persistence_inventory_cache))
		for(var/key in GLOB.persistence_inventory_cache)
			if(length(key) > plen && copytext(key, 1, plen + 1) == prefix)
				chars |= copytext(key, plen + 1)

	if(islist(GLOB.persistence_health_cache))
		for(var/key in GLOB.persistence_health_cache)
			if(length(key) > plen && copytext(key, 1, plen + 1) == prefix)
				chars |= copytext(key, plen + 1)

	if(islist(GLOB.persistence_position_cache))
		for(var/key in GLOB.persistence_position_cache)
			if(length(key) > plen && copytext(key, 1, plen + 1) == prefix)
				chars |= copytext(key, plen + 1)

	return chars

// ============================================================
// FACTION CARGO TELEPAD DELIVERY
// ============================================================

/**
 * Find an available cargo telepad for the given network.
 * Priority: faction telepad  public telepad  null (caller falls back to ship).
 */
/proc/persistence_find_cargo_telepad(network = null)
	// Normalize both sides -- pads restored from older saves or configured
	// via beacons may carry raw display-name uids
	network = normalize_faction_uid(network)
	if(network)
		for(var/obj/structure/machinery/telepad_cargo/pad in world)
			if(!pad.accepts_cargo) continue // security pads (and any future non-cargo subtype) never take deliveries
			if(!pad.z) continue
			if(!pad.persistent_spawn)  continue
			if(normalize_faction_uid(pad.persistent_network) == network)
				return get_turf(pad)

	// Public fallback
	for(var/obj/structure/machinery/telepad_cargo/pad in world)
		if(!pad.accepts_cargo) continue
		if(!pad.z) continue
		if(lowertext(pad.persistent_network) == "public" && pad.persistent_spawn)
			return get_turf(pad)

	return null

/**
 * Teleport a list of atoms to the destination turf with a flash effect.
 */
/proc/persistence_telepad_deliver(list/items, turf/destination)
	if(!destination || !length(items))
		return
	for(var/atom/movable/A in items)
		if(QDELETED(A)) continue
		A.forceMove(destination)
	// Visual/audio feedback at the destination
	playsound(destination, 'sound/effects/phasein.ogg', 50, 1)

// ============================================================
// NEURAL LACE ADMIN VERB
// ============================================================

/datum/admins/proc/install_neural_lace()
	set name = "Install Neural Lace"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/mob/target = tgui_input_list(usr, "Select target player:", "Install Neural Lace", GLOB.player_list)
	if(!target || !istype(target, /mob/living/carbon/human)) return

	var/mob/living/carbon/human/H = target

	// Check if already installed
	for(var/obj/item/organ/internal/neural_lace/existing in H.internal_organs)
		to_chat(usr, SPAN_WARNING("[H.real_name] already has a neural lace installed."))
		return

	var/confirm = tgui_alert(usr, "Install a neural lace in [H.real_name]? This will bind their consciousness to it.", "Confirm Install", list("Install", "Cancel"))
	if(confirm != "Install") return

	var/obj/item/organ/internal/neural_lace/lace = new /obj/item/organ/internal/neural_lace(H)
	lace._bind_to_owner(H)
	// Insert into head
	var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
	if(head)
		head.internal_organs |= lace
	H.internal_organs |= lace
	H.internal_organs_by_name[lace.organ_tag] = lace
	lace.owner = H

	to_chat(usr, SPAN_GOOD("Neural lace installed in [H.real_name]."))
	log_and_message_admins("installed neural lace in [H.real_name]", usr)
	feedback_add_details("admin_verb", "INL")

// ============================================================
// CRYOPOD NETWORK CONFIGURATION
// ============================================================
// Faction-network assignment AND the "public spawn point" designation are
// both configured via the faction tagger tool now (see faction_tagger_set()
// in persistence_faction_tagger.dm and the "toggle_public_spawn" ui_act
// handler in code/game/objects/items/devices/faction_tagger.dm, admin-only)
// -- no standalone verb lives here anymore.

// ============================================================
// CHARACTER SLOT SYSTEM
// ============================================================

/**
 * Returns the number of character slots for a given ckey.
 * Admins get PERSISTENCE_ADMIN_SLOTS; players get PERSISTENCE_BASE_SLOTS
 * unless overridden in ss13_character_slots.
 */
/proc/persistence_get_character_slots(ckey)
	// Check per-player override in DB
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/q = SSdbcore.NewQuery(
			"SELECT slot_limit FROM ss13_character_slots WHERE ckey = :ckey",
			list("ckey" = ckey)
		)
		q.Execute()
		if(q.NextRow())
			var/limit = text2num(q.item[1])
			qdel(q)
			return limit
		qdel(q)

	// Admin default
	var/client/C = GLOB.directory[ckey]
	if(C && C.holder && (C.holder.rights & R_ADMIN))
		return PERSISTENCE_ADMIN_SLOTS

	return PERSISTENCE_BASE_SLOTS

// ============================================================
// ADMIN VERB  set slot limit
// ============================================================

/datum/admins/proc/set_player_character_slots()
	set name = "Set Character Slots"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/target_ckey = tgui_input_text(usr, "Enter the ckey of the player to adjust:", "Set Character Slots", max_length = 32)
	if(!target_ckey)
		return

	var/new_limit = tgui_input_number(usr, "New slot limit for [target_ckey] (110):", "Set Character Slots", 1, 10, 1)
	if(!new_limit || new_limit < 1 || new_limit > 10)
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled."))
		return

	if(!SSpersistence.databaseCheckConnection("set_player_character_slots"))
		to_chat(usr, SPAN_WARNING("Database connection failed."))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_character_slots (ckey, slot_limit) VALUES (:ckey, :limit)
		ON DUPLICATE KEY UPDATE slot_limit = VALUES(slot_limit)"},
		list("ckey" = target_ckey, "limit" = new_limit)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "set_player_character_slots")
	qdel(q)

	log_and_message_admins("set character slot limit for [target_ckey] to [new_limit]", usr)
	to_chat(usr, SPAN_GOOD("Character slot limit for [target_ckey] set to [new_limit]."))
	feedback_add_details("admin_verb", "SPCS")

// ============================================================
// NEURAL LACE VAULT RESTORE
// ============================================================

/**
 * Restore vaulted neural laces from ss13_neural_lace_vault into their vaults.
 * Called from SSpersistence.Initialize() after worldstateInitialize() (vaults
 * exist and have their networks by then). Consciousnesses are round-local and
 * cannot be restored -- was_occupied is surfaced in the vault UI so an admin
 * can rebind the player via Assign Consciousness.
 */
/datum/controller/subsystem/persistence/proc/laceVaultInitialize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("laceVaultInitialize"))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, vault_x, vault_y, vault_z, registered_name, registered_ckey, owner_faction, lace_damage, was_occupied FROM ss13_neural_lace_vault WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "laceVaultInitialize"))
		qdel(q)
		return

	var/restored = 0
	var/orphaned = 0
	while(q.NextRow())
		var/row_id = text2num(q.item[1])
		var/vx = text2num(q.item[2])
		var/vy = text2num(q.item[3])
		var/vz = text2num(q.item[4])
		if(vz < 1 || vz > world.maxz)
			orphaned++
			continue
		var/turf/T = locate(vx, vy, vz)
		var/obj/structure/machinery/lace_storage/vault = T ? (locate(/obj/structure/machinery/lace_storage) in T) : null
		if(!vault || !vault.has_free_slot())
			// Leave the row -- self-heals if the vault comes back next boot.
			orphaned++
			continue
		var/obj/item/organ/internal/neural_lace/lace = new(vault)
		lace.registered_name = q.item[5] || ""
		lace.registered_ckey = q.item[6] || ""
		lace.owner_faction   = q.item[7] || ""
		lace.lace_damage     = text2num(q.item[8]) || 0
		vault.stored_laces += lace
		vault.stored_lace_row_ids += row_id
		vault.stored_lace_was_occupied += (text2num(q.item[9]) ? TRUE : FALSE)
		vault.update_icon()
		restored++
	qdel(q)
	log_subsystem_persistence_info("LaceVault: Restored [restored] vaulted lace(s)[orphaned ? ", [orphaned] row(s) left pending (no vault at coords)" : ""].")

#undef PERSISTENCE_CRYO_TIMEOUT
#undef PERSISTENCE_BASE_SLOTS
#undef PERSISTENCE_ADMIN_SLOTS
