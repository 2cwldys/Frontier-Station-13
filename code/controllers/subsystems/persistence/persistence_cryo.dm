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
 * Called from /client/Destroy() when a player disconnects.
 * Saves character state and starts the despawn countdown.
 */
/datum/controller/subsystem/persistence/proc/persistCharacterOnLogout(mob/living/carbon/human/H)
	if(!GLOB.config.sql_enabled)
		return
	if(!H || QDELETED(H))
		return
	if(!H.ckey || !H.real_name)
		return
	// Use get_turf() rather than H.z directly  when H is inside a cryopod or other
	// container, H.z is 0 (not on a turf directly). get_turf() resolves through containers.
	var/turf/H_turf = get_turf(H)
	if(!H_turf || !H_turf.z)
		return

	if(!databaseCheckConnection("persistCharacterOnLogout"))
		return

	mobPositionSave(H)
	mobsHealthSaveOne(H)
	mobsInventorySaveOne(H)
	charIdentitySaveOne(H)

	H.persistence_stored_ckey = H.ckey
	H.persistence_in_cryo     = TRUE

	// Safety net: if the mob is somehow inside a cryopod, eject them immediately
	// so the pod is not blocked for other players spawning there.
	if(istype(H.loc, /obj/structure/machinery/cryopod))
		var/obj/structure/machinery/cryopod/pod = H.loc
		var/turf/exit_turf = get_step(pod, pod.dir)
		if(!exit_turf)
			exit_turf = get_turf(pod)
		H.forceMove(exit_turf)
		if(pod.occupant == H)
			pod.occupant = null  // Explicitly clear occupant in case Exited() doesn't

	var/datum/callback/cryo_cb = new /datum/callback(H, TYPE_PROC_REF(/mob/living/carbon/human, persistence_cryo_despawn))
	H.persistence_cryo_timer = addtimer(cryo_cb, PERSISTENCE_CRYO_TIMEOUT, TIMER_STOPPABLE | TIMER_DELETE_ME)

	log_subsystem_persistence_info("Cryo: [H.real_name] ([H.ckey]) saved and entering cryosleep.")

/**
 * Intentional store: saves the character, immediately moves the mob to a player storage
 * telepad, and returns the client to the new_player lobby so they can Join again later.
 * Unlike persistCharacterOnLogout() this does NOT use a timer  storage is instant.
 */
/datum/controller/subsystem/persistence/proc/persistStoreCharacter(mob/living/carbon/human/H)
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
		log_subsystem_persistence_info("Cryo: [H.real_name] stored  no telepad found, mob remains at current location.")

	return TRUE

// ============================================================
// ENTER CRYOSLEEP VERB  manual logout via cryopod
// ============================================================

/mob/living/carbon/human/verb/enter_cryosleep()
	set name = "Enter Cryopod"
	set category = "Persistence"
	set desc = "Enter a nearby cryopod to save your character and go offline."

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
	if(!SSpersistence.persistStoreCharacter(src))
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
	if(!gc_destroyed && mob && istype(mob, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = mob
		if(H.ckey && H.real_name && !QDELETED(H))
			SSpersistence.persistCharacterOnLogout(H)
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
 * Find an available cryopod using the priority cascade:
 *   1. Faction pod matching faction_uid (exclusive to that faction)
 *   2. Public or unrestricted pod (persistent_network = "public" or "", persistent_spawn = TRUE)
 *   3. Any start landmark
 * Returns the turf in front of the chosen pod, or a landmark turf.
 */
/proc/persistence_find_available_cryopod(faction_uid = null)
	// Priority 1: faction's own pods
	if(faction_uid)
		var/list/faction_pods = list()
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(!pod.z || pod.occupant) continue
			if(pod.persistent_network == faction_uid)
				faction_pods += pod
		if(length(faction_pods))
			var/obj/structure/machinery/cryopod/chosen = pick(faction_pods)
			var/turf/step = get_step(chosen, chosen.dir)
			return step ? step : get_turf(chosen)

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
		var/is_open = (pod.persistent_network == "public")
		if(is_open && pod.persistent_spawn)
			public_pods += pod
		else
			log_subsystem_persistence_info("Cryo spawn: skipping [pod.type] at ([pod.x],[pod.y],[pod.z])  network='[pod.persistent_network]' spawn=[pod.persistent_spawn]")
	log_subsystem_persistence_info("Cryo spawn: checked [total_pods] pods, found [length(public_pods)] public/unrestricted.")
	if(length(public_pods))
		var/obj/structure/machinery/cryopod/chosen = pick(public_pods)
		var/turf/step = get_step(chosen, chosen.dir)
		return step ? step : get_turf(chosen)

	// Last resort: any start landmark
	for(var/obj/effect/landmark/start/L in world)
		return get_turf(L)
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
	var/near_pod = istype(loc, /obj/structure/machinery/cryopod)
	if(!near_pod)
		for(var/obj/structure/machinery/cryopod/pod in range(1, src))
			near_pod = TRUE
			break
	if(!near_pod)
		to_chat(src, SPAN_WARNING("You must be inside or adjacent to a cryopod to store your character."))
		return

	var/confirm = tgui_alert(src, "Store your character and go offline? Your character will be saved and moved to a safe holding area until you reconnect.", "Store Character", list("Store", "Cancel"))
	if(confirm != "Store")
		return

	// Save character and immediately move mob to player storage telepad
	if(!SSpersistence.persistStoreCharacter(src))
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
			if(!pad.z) continue
			if(!pad.persistent_spawn)  continue
			if(normalize_faction_uid(pad.persistent_network) == network)
				return get_turf(pad)

	// Public fallback
	for(var/obj/structure/machinery/telepad_cargo/pad in world)
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
// CRYOPOD NETWORK ADMIN VERB
// ============================================================

/obj/structure/machinery/cryopod/verb/configure_network()
	set name = "Configure Cryopod Network"
	set category = "Persistence"
	set desc = "Set this cryopod's persistent network and spawn designation."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	var/current = "[persistent_network ? persistent_network : "(none)"] | spawn=[persistent_spawn]"
	to_chat(usr, SPAN_NOTICE("Current config: [current]"))

	var/new_network = tgui_input_text(usr, "Enter network ID ('public' for public spawn, a faction UID for faction-only, or leave blank to clear):", "Configure Cryopod", persistent_network, max_length = 32)
	if(new_network == null)
		return

	persistent_network = (new_network == "public") ? new_network : normalize_faction_uid(new_network)

	if(new_network == "public")
		var/spawn_choice = tgui_alert(usr, "Mark this pod as a public spawn point (new arrivals emerge here)?", "Configure Cryopod", list("Yes", "No"))
		persistent_spawn = (spawn_choice == "Yes")
	else
		persistent_spawn = FALSE

	var/label = persistent_network ? "[persistent_network][persistent_spawn ? " (spawn)" : ""]" : "unrestricted"
	to_chat(usr, SPAN_GOOD("Cryopod network set to: [label]"))
	log_admin("[key_name(usr)] configured cryopod at ([x],[y],[z]) network='[persistent_network]' spawn=[persistent_spawn]")

	// Spawned cryopods register with persistent_objects so they are re-created on server restart.
	// Map-placed cryopods use worldstate instead (handled automatically).
	if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

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

#undef PERSISTENCE_CRYO_TIMEOUT
#undef PERSISTENCE_BASE_SLOTS
#undef PERSISTENCE_ADMIN_SLOTS
