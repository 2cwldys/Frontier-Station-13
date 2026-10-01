/*
 * Drydock control console -- sets who may stash, retrieve or commission a ship at
 * the drydock it is standing on.
 *
 * Deliberately the WEAKER of the two policy sources. A faction or hub beacon whose
 * claim reaches this z wins outright (drydock_policy_for_z(),
 * persistence_shuttles.dm), so this console only decides anything at a drydock
 * nobody has claimed with a beacon. That keeps a captured console from punching a
 * hole in a faction's own territory.
 *
 * Refuses to do anything at all off a drydock: the site has to have been founded as
 * one (colony radio, or the "View Drydocks" verb), since a policy for a site that
 * cannot handle ships would be meaningless.
 */
/obj/structure/machinery/computer/drydock_control
	name = "drydock control console"
	desc = "Registers a drydock's berthing rights with the local traffic authority."
	icon_keyboard = "tech_key"
	icon_screen = "shuttle"
	density = TRUE
	anchored = FALSE // spawns loose on purchase -- wrench it down before it registers
	maxhealth = OBJECT_HEALTH_HIGH
	circuit = null

	/// Faction tagger compatible -- "" (untagged), "public", or a real faction_uid.
	/// The faction this console speaks for; an untagged console can still close a
	/// drydock, it just has nobody to admit.
	var/persistent_network = ""
	/// One of DRYDOCK_POLICY_* (code/__DEFINES/persistence.dm).
	var/drydock_stash_policy = DRYDOCK_POLICY_ALL

/obj/structure/machinery/computer/drydock_control/Destroy()
	_unregister_drydock_console()
	return ..()

/obj/structure/machinery/computer/drydock_control/Initialize()
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/obj/structure/machinery/computer/drydock_control/LateInitialize()
	. = ..()
	_sync_drydock_console()

// ------- Faction tagger compatibility, same shape as guard_beacon.dm -------

/obj/structure/machinery/computer/drydock_control/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/computer/drydock_control/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/computer/drydock_control/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid || ""
	_sync_drydock_console()
	return TRUE

/**
 * Publishes this console's policy into GLOB.drydock_console_by_z, or withdraws it.
 *
 * Only an anchored console on an actual drydock registers -- an unanchored one has
 * not been installed yet, and one off a drydock has nothing to govern. Keyed by z
 * rather than by object, because that is the question drydock_policy_for_z() asks.
 */
/obj/structure/machinery/computer/drydock_control/proc/_sync_drydock_console()
	_unregister_drydock_console()
	var/my_z = GET_Z(src)
	if(!my_z || !anchored || !drydock_z_is_drydock(my_z))
		return
	GLOB.drydock_console_by_z["[my_z]"] = list(
		"policy" = drydock_stash_policy,
		"faction_uid" = normalize_faction_uid(persistent_network)
	)

/// Drops this console's claim on whichever z it last registered under. Scans rather
/// than remembering the z, so a console that was moved cannot leave a stale entry
/// behind pointing at a policy nothing enforces any more.
/obj/structure/machinery/computer/drydock_control/proc/_unregister_drydock_console()
	var/my_z = GET_Z(src)
	if(my_z && GLOB.drydock_console_by_z["[my_z]"])
		GLOB.drydock_console_by_z -= "[my_z]"

/// Wrench to (un)anchor, same shape as faction_beacon.dm's own handler.
/obj/structure/machinery/computer/drydock_control/attackby(obj/item/attacking_item, mob/user)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		user.visible_message(SPAN_NOTICE("[user] [anchored ? "wrenches" : "unwrenches"] \the [src] [anchored ? "to" : "from"] the floor."), \
			SPAN_NOTICE("You [anchored ? "wrench \the [src] to" : "unwrench \the [src] from"] the floor."))
		_sync_drydock_console()
		return TRUE
	return ..()

// ------- Reboot persistence -- auto-registered by structures.dm's Initialize(),
// this only fills in the config the base content doesn't carry. -------

/obj/structure/machinery/computer/drydock_control/persistent_objects_get_content()
	var/list/content = ..()
	content["persistent_network"] = persistent_network
	content["drydock_stash_policy"] = drydock_stash_policy
	return content

/obj/structure/machinery/computer/drydock_control/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["persistent_network"]))
		persistent_network = content["persistent_network"]
	if(!isnull(content["drydock_stash_policy"]))
		drydock_stash_policy = content["drydock_stash_policy"] || DRYDOCK_POLICY_ALL
	_sync_drydock_console()

// ------- TGUI -------

/obj/structure/machinery/computer/drydock_control/attack_hand(mob/user)
	if(..())
		return TRUE
	ui_interact(user)
	return TRUE

/obj/structure/machinery/computer/drydock_control/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "DrydockControl", "Drydock Control", 420, 360)
		ui.open()

/obj/structure/machinery/computer/drydock_control/ui_data(mob/user)
	var/list/data = list()
	var/my_z = GET_Z(src)
	data["anchored"] = anchored
	data["on_drydock"] = drydock_z_is_drydock(my_z)
	data["faction_uid"] = persistent_network
	data["faction_name"] = persistent_network ? get_faction_name(persistent_network) : null
	data["drydock_stash_policy"] = drydock_stash_policy
	data["can_configure"] = can_configure_faction_shackle(user, persistent_network, FACTION_RANK_OFFICER) ? TRUE : FALSE

	// Whether a beacon is overriding this console right now, so nobody spends ten
	// minutes wondering why their setting does nothing.
	var/obj/structure/machinery/faction_beacon/B = my_z ? get_owning_faction_beacon(my_z) : null
	data["overridden_by"] = B ? (B.faction_uid ? get_faction_name(B.faction_uid) : "an untagged beacon") : null
	data["legacy_stashing"] = GLOB.drydock_legacy_stashing
	return data

/obj/structure/machinery/computer/drydock_control/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("set_policy")
			if(!drydock_z_is_drydock(GET_Z(src)))
				to_chat(user, SPAN_WARNING("\The [src] isn't on a drydock -- there's nothing for it to govern."))
				return
			if(!can_configure_faction_shackle(user, persistent_network, FACTION_RANK_OFFICER))
				to_chat(user, SPAN_WARNING("You need command access in [persistent_network ? get_faction_name(persistent_network) : "this console's faction"] to change this."))
				return
			var/new_policy = params["policy"]
			if(!(new_policy in list(DRYDOCK_POLICY_ALL, DRYDOCK_POLICY_FACTION, DRYDOCK_POLICY_ALLIED, DRYDOCK_POLICY_NONE)))
				return
			drydock_stash_policy = new_policy
			_sync_drydock_console()
			to_chat(user, SPAN_GOOD("Drydock berthing rights set to [drydock_stash_policy]."))
			log_game("[key_name(user)] set drydock console at ([x],[y],[z]) berthing rights to [drydock_stash_policy].")
			. = TRUE
