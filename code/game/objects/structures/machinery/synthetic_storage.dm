/*
 * Synthetic Storage
 *
 * The cyborg/IPC counterpart to a cryopod (cryopod.dm) -- but ALSO a real
 * recharge station, not just reskinned to look like one. Subtypes
 * /obj/structure/machinery/recharge_station (rechargestation.dm) directly,
 * inheriting its cell/process()/process_occupant()/build_overlays() wholesale
 * -- an occupant charges (and, for a cyborg, gets welded/wired repairs) the
 * exact same way sitting in an ordinary recharge station already works,
 * for however long they stay. Entering just occupies the unit, same as any
 * recharge station; "Decommission"/"Store" (store_synthetic() below) is a
 * separate, deliberate action, mirroring how a cryopod separates "get in
 * the pod" from the explicit Store Character verb.
 *
 * Accepts /mob/living/silicon/robot AND an IPC (/mob/living/carbon/human
 * with an uncloneable synthetic species -- species_organically_cloneable(),
 * mob_helpers.dm; NOT isipc(), which also catches Android, and Android
 * keeps using normal cryopods AND normal recharge stations since it eats/
 * drinks for power -- a biological reactor, hardcoded, android.dm's own
 * doc comment). Cryopods refuse the same IPC check
 * (cryopod.dm's check_occupant_allowed()) -- the two machines are mutually
 * exclusive gates on the same species split.
 *
 * The two mob types are persisted through entirely different pipelines,
 * branched on inside store_synthetic() below: a cyborg gets the ckey-only
 * cyborg-shaped snapshot this file's own persistence_cyborg.dm builds; an
 * IPC gets the SAME (ckey, char_name)-keyed human persistence every other
 * human character already uses (persistStoreCharacter(), persistence_cryo.dm)
 * -- completely unchanged, just reached through this machine instead of a
 * cryopod, with its own last-used location tracked separately
 * (last_synth_x/y/z on ss13_mob_position, NOT last_pod_x/y/z -- see
 * persistence_set_last_synthetic_storage()'s own doc comment for why
 * sharing those columns would be wrong).
 *
 * Faction/personal/crew tagging mirrors the same interface the clone pod,
 * resleever, and prosthetics fabricator already implement this same
 * persistence effort, plus the same public/disabled semantics cryopods get
 * from the faction tagger tool (persistence_faction_tagger.dm's
 * toggle_synthetic_storage_public_spawn/toggle_synthetic_storage_disabled
 * actions).
 *
 * Decommissioning saves the occupant's full state then returns the player
 * to the character-select lobby, the same clean hand-off store_character()
 * uses for humans. A stored cyborg shows up as its own synthetic entry
 * there (persistent_menu.dm); a stored IPC is already a normal
 * ss13_characters row and shows up like any other saved character.
 * Clicking Play routes to PersistentAutoSpawnCyborg() (cyborg) or
 * PersistentAutoSpawn()'s own IPC-aware cascade branch (IPC) --
 * new_player.dm -- both reusing the exact same last-used/tiered-discovery
 * cascade shape cryopods use. The right-click "Retrieve Cyborg" verb below
 * stays as a secondary manual option for someone already standing at a
 * unit mid-round without going through the lobby at all -- it places the
 * reconstructed chassis as this unit's occupant too, so it starts charging
 * immediately rather than just being dropped nearby.
 */

/obj/structure/machinery/recharge_station/synthetic_storage
	name = "synthetic storage unit"
	desc = "A combination charging and decommissioning unit for synthetic chassis."

	/// Faction UID this unit is tagged to, "public", or "" (unmanaged).
	var/persistent_network = ""
	/// ckey this unit is personally tagged to, or null. Mutually exclusive
	/// with persistent_network.
	var/personal_ckey = null
	var/personal_char_name = null
	/// Manually disabled via the faction tagger -- refuses ALL entries
	/// regardless of network/personal tag state, same semantics as a
	/// cryopod's own tagger_disabled (persistence_cryo.dm).
	var/tagger_disabled = FALSE
	/// If TRUE and persistent_network == "public", this unit is a valid
	/// last-resort/public spawn point for the synthetic spawn cascade --
	/// same separate toggle a cryopod's own persistent_spawn is
	/// (persistence_cryo.dm), independent of just being tagged public.
	var/persistent_spawn = FALSE
	/// TRUE if reserved for a drydock ship's crew (owner + crew ckeys) --
	/// mutually exclusive with persistent_network/personal_ckey, same as a
	/// cryopod's own crew_tagged (persistence_cryo.dm).
	var/crew_tagged = FALSE
	/// How long a connected-but-idle occupant can sit before being force-
	/// stored -- same value and intent as a cryopod's own time_till_force_cryo
	/// (cryopod.dm). No time_till_despawn/grace-period or despawn_occupant()
	/// equivalent here: unlike a cryopod, every occupant _accepts() allows is
	/// a ckey'd robot or IPC-species human, fully persistence-tracked by
	/// definition, so there's no legacy non-persistence body to strip-and-
	/// ghost the way a cryopod sometimes still has to.
	var/time_till_force_cryo = 3000
	/// world.time this unit's current occupant moved in, for the AFK check
	/// above -- set in go_in() and retrieve_cyborg() below.
	var/time_entered = 0

	worldstate_vars = list("persistent_network", "personal_ckey", "personal_char_name", "tagger_disabled", "persistent_spawn", "crew_tagged")

/obj/structure/machinery/recharge_station/synthetic_storage/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/recharge_station/synthetic_storage/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/recharge_station/synthetic_storage/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	personal_ckey = null
	personal_char_name = null
	crew_tagged = FALSE
	return TRUE

/obj/structure/machinery/recharge_station/synthetic_storage/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/structure/machinery/recharge_station/synthetic_storage/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	persistent_network = ""
	crew_tagged = FALSE
	return TRUE

/obj/structure/machinery/recharge_station/synthetic_storage/crew_tagger_is_set()
	return crew_tagged

/obj/structure/machinery/recharge_station/synthetic_storage/crew_tagger_set(mob/user)
	crew_tagged = TRUE
	// Mutually exclusive with a faction/personal tag.
	persistent_network = ""
	persistent_spawn = FALSE
	personal_ckey = null
	personal_char_name = null
	return TRUE

/// TRUE for a cyborg, or an IPC (human with an uncloneable synthetic
/// species) -- the exact same split cryopod.dm's check_occupant_allowed()
/// now refuses on the other side of. See this file's own doc comment for
/// why species_organically_cloneable() and not isipc().
/obj/structure/machinery/recharge_station/synthetic_storage/proc/_accepts(mob/living/M)
	if(isrobot(M))
		return TRUE
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		return H.species && !species_organically_cloneable(H.species)
	return FALSE

/// Overrides recharge_station's own attackby() entirely (grab handling,
/// haul timing) with this file's own species gate and confirmation flow --
/// still falls through to ..() for tool/deconstruction handling.
/obj/structure/machinery/recharge_station/synthetic_storage/attackby(obj/item/attacking_item, mob/user)
	var/obj/item/grab/G = attacking_item
	if(istype(G))
		if(!_accepts(G.affecting))
			to_chat(user, SPAN_WARNING("\The [src] only accepts synthetic chassis."))
			return TRUE
		go_in(user, G.affecting)
		return TRUE
	return ..()

/// recharge_station's own CollidedWith() calls go_in(bumped_atom) with a
/// single argument, matching the base's one-arg go_in(mob/living/M) -- this
/// subtype's go_in() takes (user, M, willing) instead, so bumping in would
/// otherwise bind user=bumped_atom, M=null and silently misfire. Bump-to-
/// enter isn't part of this machine's own design (move_inside()/attackby()/
/// mouse_drop_receive() are the intended entry points), so just don't act
/// on a bump rather than adapting the call.
/obj/structure/machinery/recharge_station/synthetic_storage/CollidedWith(atom/bumped_atom)
	return

/obj/structure/machinery/recharge_station/synthetic_storage/mouse_drop_receive(atom/dropped, mob/user, params)
	if(!istype(user, /mob/living))
		return
	if(!_accepts(dropped))
		to_chat(user, SPAN_WARNING("\The [src] only accepts synthetic chassis."))
		return
	go_in(user, dropped)

/obj/structure/machinery/recharge_station/synthetic_storage/verb/move_inside()
	set name = "Enter Storage"
	set category = "Object"
	set src in oview(1)

	if(!_accepts(usr))
		to_chat(usr, SPAN_WARNING("\The [src] only accepts synthetic chassis."))
		return
	go_in(usr, usr, TRUE)

/**
 * Occupies the unit -- willing-check, faction gate, do_after -- then just
 * sets occupant, same as any recharge station. No save, no decommission;
 * that's store_synthetic() below, a deliberate separate step. `user` is
 * whoever's doing the placing; `M` is the robot or IPC being placed.
 * No "proc/" prefix -- see eject()'s comment above, same reason.
 */
/obj/structure/machinery/recharge_station/synthetic_storage/go_in(mob/user, mob/living/M, willing = FALSE)
	if(tagger_disabled)
		to_chat(user, SPAN_WARNING("\The [src] is disabled and refuses to accept chassis."))
		return
	if(!_accepts(M))
		to_chat(user, SPAN_WARNING("\The [src] only accepts synthetic chassis."))
		return
	if(occupant)
		to_chat(user, SPAN_WARNING("\The [src] is already occupied."))
		return

	if(persistent_network && persistent_network != "public" && GLOB.config.sql_enabled)
		var/player_faction = M.ckey ? persistence_get_player_faction(M.ckey) : null
		if(normalize_faction_uid(player_faction) != normalize_faction_uid(persistent_network))
			to_chat(user, SPAN_WARNING("\The [src] refuses [M == user ? "you" : "\the [M]"] -- it is restricted to [persistent_network] personnel only."))
			return

	if(!willing && M.client)
		var/original_loc = M.loc
		if(alert(M, "Would you like to enter \the [src]?", "Synthetic Storage", "Yes", "No") != "Yes")
			return
		if(!M || M.loc != original_loc)
			return

	user.visible_message(
		SPAN_NOTICE("\The [user] starts easing \the [M] into \the [src]."),
		SPAN_NOTICE("You start easing \the [M] into \the [src]."),
	)
	if(!do_after(user, 2 SECONDS, M, DO_UNIQUE))
		to_chat(user, SPAN_NOTICE("You stop easing \the [M] into \the [src]."))
		return
	if(!M || QDELETED(M) || occupant)
		return

	if(!M.Move(src))
		return
	occupant = M
	time_entered = world.time
	update_icon()
	to_chat(M, SPAN_NOTICE("You settle into \the [src]. It hums as it begins charging your systems."))

/**
 * The deliberate, separate decommission step -- mirrors cryopod.dm's own
 * Store Character verb. Acts on whoever is currently occupant, not
 * necessarily usr -- same "someone else can do this for you" shape
 * go_in() already has.
 */
/obj/structure/machinery/recharge_station/synthetic_storage/verb/store_synthetic()
	set name = "Decommission Chassis"
	set category = "Object"
	set src in oview(1)

	if(!occupant)
		to_chat(usr, SPAN_WARNING("\The [src] is empty."))
		return
	var/mob/living/M = occupant
	if(!_accepts(M))
		to_chat(usr, SPAN_WARNING("\The [src]'s occupant can't be decommissioned here."))
		return
	if(!M.ckey)
		to_chat(usr, SPAN_WARNING("\The [M] has no owner to store this chassis under."))
		return
	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("Persistence is not enabled -- storage aborted."))
		return

	var/confirm = tgui_alert(usr, "Decommission [M] into long-term storage? [M == usr ? "You" : "They"] will need to reactivate from a synthetic storage unit to return.", "Decommission Chassis", list("Decommission", "Cancel"))
	if(confirm != "Decommission")
		return
	if(!occupant || occupant != M)
		to_chat(usr, SPAN_WARNING("\The [src]'s state changed while you were deciding. Aborting."))
		return

	if(isrobot(M))
		if(!SSpersistence.charCyborgSaveOne(M, get_turf(src)))
			to_chat(usr, SPAN_WARNING("\The [src] couldn't save \the [M]'s state -- storage aborted."))
			return
		to_chat(M, SPAN_NOTICE("Your chassis powers down and is decommissioned into storage. It will show up as its own entry at the character-select screen -- click Play to reactivate it."))
	else
		// IPC path: identical human persistence every other character
		// already uses (persistStoreCharacter(), persistence_cryo.dm), just
		// reached through this machine instead of a cryopod. Passing null
		// for its own "pod" param deliberately skips persistence_set_last_pod()
		// (that's cryopod-specific bookkeeping) -- last-used location is
		// tracked separately below instead.
		var/mob/living/carbon/human/H = M
		if(!SSpersistence.persistStoreCharacter(H, null))
			to_chat(usr, SPAN_WARNING("\The [src] couldn't save \the [M]'s state -- storage aborted."))
			return
		persistence_set_last_synthetic_storage(H.ckey, H.real_name, src)
		to_chat(M, SPAN_NOTICE("Your character powers down and is decommissioned into storage. Click Play to reactivate at this same unit."))

	occupant = null
	visible_message(SPAN_NOTICE("\The [src] hums and hisses as it decommissions \the [M]."))
	log_and_message_admins("decommissioned [key_name_admin(M)]'s synthetic chassis in \the [src].", usr)
	update_icon()

	// Clean return to the lobby, same hand-off store_character() uses for
	// humans (persistence_cryo.dm) -- the player lands back at character
	// select instead of being left as whatever an orphaned client defaults
	// to once M is deleted.
	var/stored_key = M.key
	if(M.client)
		M.client.stop_ambient_playlist()
	if(stored_key)
		var/mob/abstract/new_player/NP = new()
		NP.key = stored_key
	qdel(M)

/obj/structure/machinery/recharge_station/synthetic_storage/verb/retrieve_cyborg()
	set name = "Retrieve Cyborg"
	set category = "Object"
	set src in oview(1)

	if(occupant)
		to_chat(usr, SPAN_WARNING("\The [src] is already occupied."))
		return
	if(!usr.ckey)
		return
	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("Persistence is not enabled -- nothing can be retrieved."))
		return

	var/list/snapshot = SSpersistence.charCyborgResolve(usr.ckey)
	if(!snapshot)
		to_chat(usr, SPAN_WARNING("\The [src] has no stored chassis for you."))
		return

	var/turf/T = get_turf(src)
	if(!T)
		return

	var/target_ckey = usr.ckey
	var/mob/living/silicon/robot/R = SSpersistence.charCyborgRestore(target_ckey, T, snapshot)
	if(!R)
		to_chat(usr, SPAN_WARNING("\The [src] failed to reconstruct your chassis. Contact an administrator."))
		return

	// usr is already a live, embodied mob here (unlike the lobby spawn
	// path's fresh mob) -- move the mind properly rather than assigning the
	// key directly, which would leave usr's own mob in an inconsistent
	// state instead of the mindless leftover a real transfer produces (same
	// as Robotize() already does elsewhere for a live human becoming a
	// cyborg).
	if(usr.mind)
		usr.mind.transfer_to(R)
	else
		R.key = target_ckey

	SSpersistence.charCyborgDelete(target_ckey)
	R.forceMove(src)
	occupant = R
	time_entered = world.time
	update_icon()
	visible_message(SPAN_NOTICE("\The [src] hums and hisses as it reactivates a synthetic chassis."))
	to_chat(R, SPAN_GOOD("You power back on. Welcome back."))
	log_and_message_admins("retrieved a stored cyborg chassis from \the [src].", R)

/**
 * Mirrors cryopod.dm's own process() disconnect/AFK auto-store handling --
 * an occupant who closes their client, or sits connected-but-idle past
 * time_till_force_cryo, gets force-stored instead of occupying the unit
 * forever and blocking anyone else from using it.
 */
/obj/structure/machinery/recharge_station/synthetic_storage/process(seconds_per_tick)
	if(occupant && occupant.ckey && occupant.stat != DEAD && GLOB.config.sql_enabled)
		if(!occupant.client)
			if(persistence_force_store_synthetic())
				return
		else if(world.time - time_entered > time_till_force_cryo)
			if(persistence_force_store_synthetic())
				return
	return ..()

/**
 * Force-stores whoever is occupying the unit -- called from process() on a
 * disconnect or AFK timeout, the same triggers cryopod.dm's own
 * persistence_force_store() responds to. No confirmation dialog (there's no
 * one left to confirm with in the disconnect case, and the AFK case is the
 * same call a cryopod already makes on its own occupant's behalf). A
 * disconnected occupant's key is just cleared; a connected-but-AFK one gets
 * the same clean lobby return store_synthetic() gives someone who
 * decommissions on purpose.
 */
/obj/structure/machinery/recharge_station/synthetic_storage/proc/persistence_force_store_synthetic()
	var/mob/living/M = occupant
	if(!istype(M) || !M.ckey || M.stat == DEAD || !GLOB.config.sql_enabled)
		return FALSE
	if(!_accepts(M))
		return FALSE

	if(isrobot(M))
		if(!SSpersistence.charCyborgSaveOne(M, get_turf(src)))
			return FALSE
	else
		var/mob/living/carbon/human/H = M
		if(!SSpersistence.persistStoreCharacter(H, null))
			return FALSE
		persistence_set_last_synthetic_storage(H.ckey, H.real_name, src)

	occupant = null
	update_icon()
	log_subsystem_persistence_info("SyntheticStorage: force-stored [key_name(M)] ([M.client ? "AFK" : "disconnected"]) in [src] at [COORD(src)].")

	if(M.client)
		var/stored_key = M.key
		M.client.stop_ambient_playlist()
		var/mob/abstract/new_player/NP = new()
		NP.key = stored_key
		to_chat(NP, SPAN_NOTICE("You were stored in synthetic storage. Click Play to return."))
	else
		M.key = null

	qdel(M)
	return TRUE
