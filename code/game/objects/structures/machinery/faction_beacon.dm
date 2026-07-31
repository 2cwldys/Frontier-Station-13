/*
 * Faction Beacon
 * A single placeable object that anchors a faction's territory to an entire
 * Z-level. Every compatible object/area on that Z-level automatically
 * inherits the faction's persistent_network, so admins configure one object
 * instead of each cryopod, telepad, console, telecomms machine, and
 * blueprint-created area individually. Every site this codebase deals with
 * is single-faction territory, so whole-Z-level scope (not a configurable
 * radius) is the intended design -- see GLOB.faction_beacon_by_z below for
 * how a second beacon on the same Z-level is handled.
 *
 * Claiming a Z-level (successful _apply_network()) also ensures that Z is in
 * the persistence save list and bumps its security to at least medsec.
 * Destroying the beacon by damage reverses both -- the Z stops saving and
 * drops to nullsec -- the "station becomes defeated" mechanic. Admin
 * deletion and any future tool-deconstruction path deliberately do NOT
 * trigger this (see on_death()/destroyed_by_damage below).
 */

/// How often an active, powered beacon re-sweeps for newly-placed
/// unassigned objects (process(), _sweep_unassigned_objects_for_faction()) --
/// catches anything placed after the beacon already went active, which the
/// one-time _apply_network() sweep can never see on its own.
#define FACTION_BEACON_SWEEP_INTERVAL 30 SECONDS

/// How often an active, powered beacon re-evaluates its security_radius
/// grant/revoke (_apply_security_radius_grant()) -- deliberately much
/// tighter than FACTION_BEACON_SWEEP_INTERVAL (unassigned-object sweep,
/// hazard eviction), since this drives player-visible zone detection
/// (overmap outline, chat/sound announcement) and should feel responsive.
#define FACTION_BEACON_SECURITY_SWEEP_INTERVAL 5 SECONDS

/// How often (while operating) a beacon's fuel reserve drains, and by how
/// much. Shared by faction_beacon.dm and piracy_beacon.dm. ~100 credits/hour
/// -- a full 50000 reserve lasts ~3 weeks of continuous operation.
/// Deliberately much slower than portgen/basic's real-time sheet burn
/// (hours) -- tune these two defines if the cadence feels off.
#define BEACON_FUEL_DRAIN_INTERVAL 10 MINUTES
#define BEACON_FUEL_DRAIN_AMOUNT 25

/obj/structure/machinery/faction_beacon
	name = "faction beacon"
	desc = "An anchor beacon that ties nearby infrastructure to a faction network."
	icon = 'icons/obj/machinery/telecomms.dmi'
	icon_state = "bspacerelay"
	anchored = TRUE // default -- can be wrenched loose (see attackby()) once powered off
	density = FALSE
	layer = OBJ_LAYER
	maxhealth = OBJECT_HEALTH_HIGH // hard to destroy by accident, not immune to a real assault

	/// Faction UID this beacon represents (e.g. "nanotrasen", "zavodskoi")
	var/faction_uid = ""
	/// Whether this beacon is actively networked
	var/active = FALSE
	/// Manual on/off -- an unpowered beacon can never hold a Z claim, letting
	/// command deliberately hand a Z off to a different beacon without
	/// having to destroy the old one first. Spawns off -- must be deliberately
	/// powered up via the TGUI, never active out of the box.
	var/powered = FALSE
	/// Alt-click to toggle (mirrors APC/air alarm's lock pattern) -- while
	/// locked, only admins can use the TGUI's power toggle. Secure by default.
	var/locked = TRUE
	/// Faction opt-out of the global faction raiding toggle
	/// (GLOB.faction_raiding_enabled, persistence_factions.dm) -- when TRUE,
	/// non-members may always enter this beacon's Z(s), even while raiding is
	/// admin-disabled server-wide. FALSE by default (subject to the global
	/// toggle like every other beacon). Faction command-toggleable via the
	/// TGUI ("toggle_public_territory"), same can_configure_faction_shackle()
	/// gate as every other faction-side control here.
	var/public_territory = FALSE
	/// How many overmap sectors out (in addition to this beacon's own Z) get
	/// their security bumped to at least medsec when the network applies.
	/// Admin-adjustable via the TGUI. 0 = only this beacon's own Z, matching
	/// the original design before this was added.
	var/security_radius = 1
	/// Minimum security tier this beacon's claim guarantees, for both its own
	/// Z and the overmap security radius -- never downgrades a Z already at
	/// or above this tier. ZONE_MEDSEC for the standard beacon; the hub
	/// beacon variant (below) raises this to ZONE_HIGHSEC.
	var/guaranteed_security_tier = ZONE_MEDSEC
	/// Z's currently granted guaranteed_security_tier via this beacon's
	/// security_radius reach -- recomputed every _apply_security_radius_grant()
	/// call and diffed against the previous sweep's set so a Z that falls OUT
	/// of range gets released too, not just raised and left stuck. Never
	/// contains this beacon's own station Zs -- those are a separate,
	/// whole-level ownership model this doesn't touch.
	var/list/granted_neighbor_zs = list()
	/// Set just before qdel() when health hit zero (see on_death()) --
	/// distinguishes genuine combat destruction from admin qdel/VV-delete
	/// and any future tool-deconstruction path, neither of which call
	/// on_death() at all.
	var/destroyed_by_damage = FALSE
	/// Sparks while active, for a visible "this is online" tell.
	var/datum/effect_system/sparks/spark_system
	/// Looping hum while active, same visible-online purpose as the sparks.
	var/looping_sound_type = /datum/looping_sound/faction_beacon
	VAR_PRIVATE/datum/looping_sound/beacon_looping_sound
	/// world.time of the next periodic unassigned-object re-sweep -- see
	/// process()/_sweep_unassigned_objects_for_faction(). Catches objects
	/// placed AFTER the beacon already went active, which the one-time
	/// _apply_network() sweep can never see on its own.
	var/next_sweep_time = 0
	/// world.time of the next periodic security_radius grant/revoke sweep --
	/// see process()/_apply_security_radius_grant(). Runs on its own, much
	/// tighter cadence than next_sweep_time since it drives player-visible
	/// zone detection.
	var/next_security_sweep_time = 0
	/// Physical credit reserve that keeps this beacon running -- drains
	/// slowly while powered (see process()), auto-powers the beacon off at
	/// zero via _power_down(). Fed by inserting spacecash (attackby()),
	/// withdrawable via the TGUI. Fully persistent.
	var/fuel_credits = 0
	/// Hard cap on fuel_credits. Fixed per-type, not admin-adjustable.
	var/max_fuel_credits = 50000
	/// FALSE only on the hub beacon subtype -- admin-spawned, exempt entirely.
	var/requires_fuel = TRUE
	/// world.time of the next periodic fuel-drain tick, mirrors next_sweep_time.
	var/next_fuel_drain_time = 0

/// Z-number (as text) -> the faction beacon currently claiming that whole
/// Z-level. Only one beacon may be active per Z at a time -- first-placed/
/// configured takes precedence; a second beacon on the same Z is refused
/// until the first is powered off or destroyed.
GLOBAL_LIST_EMPTY(faction_beacon_by_z)

/// The active, powered faction beacon responsible for z's current security
/// tier -- either it directly owns z (GLOB.faction_beacon_by_z), or z falls
/// within its security_radius reach (mirrors _apply_security_radius_grant()'s
/// own range() sweep). Null if no beacon is responsible (admin-set security,
/// Hub-default territory with no beacon, or plain nullsec).
/proc/get_owning_faction_beacon(z)
	if(!z)
		return null
	var/obj/structure/machinery/faction_beacon/direct = GLOB.faction_beacon_by_z["[z]"]
	if(direct && !QDELETED(direct) && direct.active && direct.powered)
		return direct
	if(!SSatlas.current_map.use_overmap)
		return null
	for(var/obj/structure/machinery/faction_beacon/B in world)
		if(QDELETED(B) || !B.active || !B.powered || B.security_radius <= 0)
			continue
		var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
		if(!istype(beacon_sector))
			continue
		for(var/obj/effect/overmap/visitable/V in range(B.security_radius, beacon_sector))
			if(z in V.map_z)
				return B
	return null

/// Powers off every active faction beacon belonging to faction_uid -- called
/// only when that faction is force-delisted from the stock exchange due to
/// insolvency (stockMarketRevokeFaction(), user null), never on an admin-
/// initiated revoke for any other reason (a manual revoke leaves the
/// faction's own territory alone). _power_down() already does exactly what
/// bankruptcy should mean here: releases the Z claim, drops persistence-save,
/// reverts the security tier, and un-networks every object/area this beacon
/// had swept -- so its former territory (and everything tagged on it) goes
/// back to fully unassigned, same as if command had powered it down
/// themselves.
/proc/_power_down_faction_beacons_on_bankruptcy(faction_uid)
	if(!faction_uid)
		return
	for(var/obj/structure/machinery/faction_beacon/B in world)
		if(QDELETED(B) || B.faction_uid != faction_uid || !B.powered)
			continue
		B._power_down(null, "faction bankrupt -- stock exchange listing revoked")

/obj/structure/machinery/faction_beacon/Initialize(mapload)
	. = ..()
	spark_system = bind_spark(src, 5)
	if(faction_uid)
		_apply_network()

/obj/structure/machinery/faction_beacon/on_death()
	destroyed_by_damage = TRUE
	. = ..()

/obj/structure/machinery/faction_beacon/Destroy()
	// Releasing whatever security-tier grant this beacon held, and the
	// persistence-save flag it set, happens on ANY removal while active --
	// unlike a power-down, nothing else runs after a beacon is gone, so
	// this can't be gated on destroyed_by_damage like the louder "station
	// defeated" effects below are, or an admin deletion would leave the
	// tier/save flag stuck forever with no beacon left to release them.
	if(active)
		_release_security_grants()
		_release_persistence_save()
		_release_site_pin()
		_release_swept_objects()

	// Losing the beacon to COMBAT additionally "defeats" the station it
	// anchored -- make sure admins can't miss it. Only for genuine combat
	// destruction (see on_death()) -- admin deletion and tool disassembly
	// skip this loud messaging (they already get a quieter power-down
	// message, or none at all for a raw admin delete). The actual
	// persistence-save revert above already happened either way.
	if(destroyed_by_damage && active && faction_uid)
		var/fname = get_faction_name(faction_uid)
		message_admins("<font size='4' color='red'><b>FACTION BEACON DESTROYED:</b></font> [fname]'s beacon at ([x],[y],[z]) was destroyed -- its Z-level(s) will no longer save/persist and its security tier grants have been released. (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
		log_game("Faction beacon destroyed: [fname]'s beacon at ([x],[y],[z]) removed from persistence save list, security grants released.")
	QDEL_NULL(beacon_looping_sound)
	qdel(spark_system)
	spark_system = null
	_release_z_claim()
	return ..()

/obj/structure/machinery/faction_beacon/process()
	if(!active || !powered)
		return
	if(prob(15))
		spark_system.queue()
	if(world.time >= next_security_sweep_time)
		next_security_sweep_time = world.time + FACTION_BEACON_SECURITY_SWEEP_INTERVAL
		_apply_security_radius_grant()
		zone_security_update_overmap()
	if(world.time >= next_sweep_time)
		next_sweep_time = world.time + FACTION_BEACON_SWEEP_INTERVAL
		_sweep_unassigned_objects_for_faction(_station_zs(), faction_uid)
		_evict_hazards_in_range()
	if(requires_fuel && world.time >= next_fuel_drain_time)
		next_fuel_drain_time = world.time + BEACON_FUEL_DRAIN_INTERVAL
		fuel_credits = max(0, fuel_credits - BEACON_FUEL_DRAIN_AMOUNT)
		if(fuel_credits <= 0)
			_power_down(null, "ran out of fuel credits")

/// Wrench to (un)anchor -- moving the beacon requires unwrenching it first.
/// Must be powered off before it can be unwrenched (that already guarantees
/// no active Z claim needs releasing here), and command-tier faction access
/// is required either way, matching toggle_beacon_power()'s own gate.
/obj/structure/machinery/faction_beacon/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, /obj/item/spacecash) && !istype(attacking_item, /obj/item/spacecash/ewallet))
		if(!requires_fuel)
			to_chat(user, SPAN_WARNING("\The [src] doesn't need fuel credits."))
			return TRUE
		var/obj/item/spacecash/cash = attacking_item
		if(fuel_credits + cash.worth > max_fuel_credits)
			to_chat(user, SPAN_WARNING("\The [src] can't hold that much more -- [max_fuel_credits - fuel_credits] credits of space left."))
			return TRUE
		fuel_credits += cash.worth
		user.visible_message(SPAN_NOTICE("[user] feeds \the [cash] into \the [src]."), \
			SPAN_NOTICE("You feed [cash.worth] credits into \the [src]. Reserve: [fuel_credits]/[max_fuel_credits]."))
		qdel(cash)
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		if(anchored && powered)
			to_chat(user, SPAN_WARNING("Power down \the [src] before unwrenching it."))
			return TRUE
		if(!can_configure_faction_shackle(user, faction_uid, 1))
			to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to (un)wrench it."))
			return TRUE
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		user.visible_message(SPAN_NOTICE("[user] [anchored ? "wrenches" : "unwrenches"] \the [src] [anchored ? "to" : "from"] the floor."), \
			SPAN_NOTICE("You [anchored ? "wrench \the [src] to" : "unwrench \the [src] from"] the floor."))
		return TRUE
	return ..()

/obj/structure/machinery/faction_beacon/worldstate_get_content()
	if(!faction_uid)
		return list()
	return list("faction_uid" = faction_uid, "powered" = powered, "locked" = locked, "security_radius" = security_radius, "fuel_credits" = fuel_credits, "public_territory" = public_territory)

/obj/structure/machinery/faction_beacon/worldstate_apply_content(list/content)
	faction_uid = content["faction_uid"] || ""
	powered = isnull(content["powered"]) ? FALSE : !!content["powered"]
	locked = isnull(content["locked"]) ? TRUE : !!content["locked"]
	security_radius = isnull(content["security_radius"]) ? 1 : text2num(content["security_radius"])
	fuel_credits = isnull(content["fuel_credits"]) ? 0 : between(0, text2num(content["fuel_credits"]), max_fuel_credits)
	public_territory = isnull(content["public_territory"]) ? FALSE : !!content["public_territory"]
	if(!requires_fuel)
		powered = TRUE // admin/no-maintenance beacons (e.g. hub) never legitimately save powered-off
	if(faction_uid && powered && (!requires_fuel || fuel_credits > 0))
		_apply_network()
	else if(powered && requires_fuel && fuel_credits <= 0)
		powered = FALSE // saved in an inconsistent state -- don't silently claim with no fuel

/// Mirrors worldstate_get_content()/worldstate_apply_content() exactly --
/// non-mapload beacons (admin-spawned, or built away from the original map
/// template) auto-register into the tracked-objects persistence system
/// instead of worldstate (_machinery.dm's Initialize()), which reads these
/// overrides, not the worldstate ones. Without this, fuel_credits and every
/// other field here silently drops to the base /obj empty-list default.
/obj/structure/machinery/faction_beacon/persistent_objects_get_content()
	var/list/content = ..()
	if(!faction_uid)
		return content
	content["faction_uid"] = faction_uid
	content["powered"] = powered
	content["locked"] = locked
	content["security_radius"] = security_radius
	content["fuel_credits"] = fuel_credits
	content["public_territory"] = public_territory
	return content

/obj/structure/machinery/faction_beacon/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["faction_uid"]))     faction_uid     = content["faction_uid"] || ""
	if(!isnull(content["powered"]))         powered         = !!content["powered"]
	if(!isnull(content["locked"]))          locked          = !!content["locked"]
	if(!isnull(content["security_radius"])) security_radius = text2num(content["security_radius"])
	if(!isnull(content["fuel_credits"]))    fuel_credits    = between(0, text2num(content["fuel_credits"]), max_fuel_credits)
	if(!isnull(content["public_territory"])) public_territory = !!content["public_territory"]
	if(!requires_fuel)
		powered = TRUE // admin/no-maintenance beacons (e.g. hub) never legitimately save powered-off
	if(faction_uid && powered && (!requires_fuel || fuel_credits > 0))
		_apply_network()
	else if(powered && requires_fuel && fuel_credits <= 0)
		powered = FALSE

/// Every Z-level belonging to this beacon's own host station/site (all decks
/// of a multi-Z station connected via stairs/ladders, not just the specific
/// deck this beacon physically sits on) -- falls back to just this beacon's
/// own Z if the overmap is unavailable or its marker can't be found. For a
/// single-Z away site this is just that one Z, identical to pre-fix behavior.
/obj/structure/machinery/faction_beacon/proc/_station_zs()
	var/beacon_z = GET_Z(src)
	var/list/zs = list(beacon_z)
	if(SSatlas.current_map.use_overmap)
		var/obj/effect/overmap/visitable/my_sector = GLOB.map_sectors["[beacon_z]"]
		if(istype(my_sector) && length(my_sector.map_z))
			zs = my_sector.map_z.Copy()
	// A physically-landed drydock ship (or its sub-ship, which shares its
	// mothership's z) is never this beacon's territory, even if its z falls
	// within the same multi-deck sector -- excluding every z tracked in
	// GLOB.persistence_ship_z (persistence_shuttles.dm) keeps its equipment
	// out of every operation that funnels through this proc: the claim
	// itself, the periodic unassigned-object sweep, security-tier grants,
	// persistence-save flagging, and release.
	for(var/z in zs.Copy())
		if(GLOB.persistence_ship_z["[z]"])
			zs -= z
	return zs

/// Null if this beacon could claim/hold its station right now, otherwise a
/// short reason explaining why not -- lets callers show a specific message
/// instead of one generic blended "already claimed" line.
/obj/structure/machinery/faction_beacon/proc/_claim_refusal_reason()
	if(!anchored)
		return "not anchored -- wrench it to the floor first"
	if(!powered)
		return "not powered"
	// Any Z a live mission is currently using (auto-generated for the
	// mission, or a dynamic/admin-placed site it's reusing) is meant to
	// stay uncontrolled -- no faction may ever claim it, even if a beacon
	// gets hauled in and powered up there. Lifts on its own once the
	// mission ends (is_active_mission_sector(), persistence_missions.dm).
	if(is_active_mission_sector(GET_Z(src)))
		return "this sector is reserved for an active mission -- no faction may claim it"
	// Reuses the exact same type check persistence_pin_site_at_z() already
	// trusts to identify "this Z belongs to a ship, not a claimable site"
	// (persistence_factions.dm) -- covers a corvette's own interior Z
	// (use_mapped_z_levels=TRUE maps its marker onto that Z) and any
	// non-mapped overmap ship's own reserved landmark Z (landable.dm) alike.
	// Without this, a claim here would report active=TRUE and network
	// objects aboard, but persistence_pin_site_at_z() silently no-ops for a
	// ship Z, and the claim itself is orphaned the next time that ship's Z
	// gets torn down/abandoned (e.g. a corvette Stash).
	// Scoped to ship/landable specifically -- the class corvettes and
	// drydock ships actually use, whose Z gets torn down on Stash -- not
	// the whole ship hierarchy. ship/stationary (sensor relays and other
	// away-site installations that just use a ship-shaped overmap icon)
	// is explicitly non-flyable scenery with a normal, permanent Z, and
	// was being wrongly caught by istype() matching every ship subtype.
	var/obj/effect/overmap/visitable/sector = GLOB.map_sectors["[GET_Z(src)]"]
	if(istype(sector, /obj/effect/overmap/visitable/ship/landable))
		return "this location is aboard a ship, not a claimable site"
	// Asteroids can still passively fall within a nearby beacon's claimed
	// security radius -- this only blocks planting a beacon directly on one.
	if(is_asteroid_zone(GET_Z(src)))
		return "this is an asteroid -- it cannot be claimed directly"
	for(var/z in _station_zs())
		var/obj/structure/machinery/faction_beacon/holder = GLOB.faction_beacon_by_z["[z]"]
		if(holder && holder != src && !QDELETED(holder))
			return "Z-level [z] is already claimed by [holder.faction_uid ? get_faction_name(holder.faction_uid) : "another beacon"]"
		// ANY other active beacon's radius reach over z -- at any tier,
		// highsec or medsec -- already provides protection there; letting a
		// second beacon claim inside that radius would just nest overlapping
		// security claims for no purpose. The hub beacon is exempt -- it's
		// the one beacon allowed to anchor highsec in the first place.
		if(!istype(src, /obj/structure/machinery/faction_beacon/hub) && _max_tier_from_other_beacons(z) > ZONE_NULLSEC)
			return "this location already falls within another faction's protected radius -- no new beacon may be claimed here"
	return null

/// TRUE if this beacon currently holds (or can freely take) its station's
/// claim -- FALSE if a different, still-existing beacon already holds any
/// deck of it.
/obj/structure/machinery/faction_beacon/proc/_can_claim_z()
	return !_claim_refusal_reason()

/obj/structure/machinery/faction_beacon/proc/_release_z_claim()
	for(var/z in _station_zs())
		var/key = "[z]"
		if(GLOB.faction_beacon_by_z[key] == src)
			GLOB.faction_beacon_by_z -= key

/// Highest guaranteed_security_tier justified for nearby_z by any OTHER
/// active, powered faction beacon -- either it (or one of its own station's
/// other decks) owns nearby_z directly, or its own security_radius reaches
/// it. ZONE_NULLSEC if none. Used by _revoke_stale_neighbor_grants() so
/// releasing one beacon's grant falls back to whatever tier a DIFFERENT
/// beacon still legitimately justifies (lower, equal, or even higher than
/// this beacon's own tier) in one step, instead of always dropping to
/// nullsec and waiting for that other beacon's own next sweep to notice and
/// re-raise it.
/obj/structure/machinery/faction_beacon/proc/_max_tier_from_other_beacons(nearby_z)
	. = ZONE_NULLSEC
	for(var/obj/structure/machinery/faction_beacon/B in world)
		if(B == src || QDELETED(B) || !B.active || !B.powered)
			continue
		if(B.guaranteed_security_tier <= .)
			continue
		if(nearby_z in B._station_zs())
			. = B.guaranteed_security_tier
			continue
		if(!SSatlas.current_map.use_overmap || B.security_radius <= 0)
			continue
		var/obj/effect/overmap/visitable/other_sector = GLOB.map_sectors["[GET_Z(B)]"]
		if(!istype(other_sector))
			continue
		for(var/obj/effect/overmap/visitable/V in range(B.security_radius, other_sector))
			if(nearby_z in V.map_z)
				. = B.guaranteed_security_tier
				break

/// Reverses _apply_network()'s security-tier grants for this beacon: drops
/// every Z of its own station back to nullsec, and any nearby Z it uplifted
/// via security_radius -- but only where nothing else still justifies the
/// current tier. An admin-set tier higher than this beacon ever granted is
/// left alone (own Zs can only ever be exactly at our tier or something
/// else's doing, never ours to lower further), and a neighbor still within
/// another active beacon's equal-or-greater radius reach is left alone.
/obj/structure/machinery/faction_beacon/proc/_release_security_grants()
	var/beacon_z = GET_Z(src)
	var/list/station_zs = _station_zs()
	// Own-Z(s) and neighbor grants both only ever happen downstream of a
	// successful _claim_refusal_reason() check in _apply_network() -- if this
	// beacon isn't (or is no longer) the recorded owner of its own Z, it never
	// actually granted anything here, so there's nothing of ours to release.
	// Must be checked before _release_z_claim() runs in the caller.
	if(GLOB.faction_beacon_by_z["[beacon_z]"] != src)
		return
	for(var/z in station_zs)
		if(zone_security_get(z) == guaranteed_security_tier)
			persistence_set_zone_security(z, ZONE_NULLSEC)

	// Release every neighbor Z this beacon has EVER confirmed granted
	// (granted_neighbor_zs), not just whatever's still spatially in range --
	// a ship granted a tier while passing through, then flown far away, is
	// invisible to a live range() rescan at release time. Same guards as
	// every other sweep (still-ours-to-touch tier match, other-beacon
	// coverage) live in _revoke_stale_neighbor_grants() itself.
	_revoke_stale_neighbor_grants(list())

/// Turns persistence saving back off for every Z of this beacon's own
/// station -- called whenever the beacon stops being active (powered down,
/// deleted, or destroyed). Doesn't wipe anything; the Z just stops being
/// saved, so it comes back fresh next boot like it was never claimed.
/obj/structure/machinery/faction_beacon/proc/_release_persistence_save()
	for(var/z in _station_zs())
		SSpersistence.setZLevelPersistence(z, 0, "Faction: [faction_uid] beacon released")

/// Reverses _apply_network()'s persistence_pin_site_at_z() calls -- called
/// alongside _release_persistence_save() wherever this beacon stops being
/// active. persistence_unpin_site_at_z() only touches a site whose pin
/// notes exactly match this beacon's own pin reason, so an admin-pinned
/// (or otherwise-reasoned) site is never affected.
/obj/structure/machinery/faction_beacon/proc/_release_site_pin()
	for(var/z in _station_zs())
		persistence_unpin_site_at_z(z, "Faction: [faction_uid]")

/// Scan every compatible object/area across this beacon's entire host
/// station (every Z-level it spans, not just the deck this beacon physically
/// sits on) and set their persistent_network to our faction_uid. Refuses to
/// run (and logs why) if unpowered, or if a different, still-active beacon
/// already claims any Z of this station -- callers that need to tell a user
/// why should check _can_claim_z() themselves first for a proper chat message.
/obj/structure/machinery/faction_beacon/proc/_apply_network()
	faction_uid = normalize_faction_uid(faction_uid)
	if(!faction_uid)
		active = FALSE
		_release_z_claim()
		update_icon()
		return

	var/refusal = _claim_refusal_reason()
	if(refusal)
		active = FALSE
		log_game("Faction beacon at ([x],[y],[z]): refused to activate -- [refusal].")
		update_icon()
		return

	var/list/station_zs = _station_zs()
	for(var/z in station_zs)
		GLOB.faction_beacon_by_z["[z]"] = src
	active = TRUE

	// Visible/audible "online" tell and icon update happen immediately, not
	// after the sweep below -- if any sweep loop throws, active is already
	// TRUE and everything downstream of it must still reflect that
	// correctly instead of silently never running. Own try/catch too, since
	// this section can throw just as easily as the sweeps below it -- no
	// manual SSprocessing registration needed here, /obj/structure/machinery
	// already auto-registers every beacon with SSmachinery at spawn, and
	// process() self-gates on active/powered.
	try
		update_icon()
		if(!beacon_looping_sound)
			beacon_looping_sound = new looping_sound_type(src)
			beacon_looping_sound.start()
	catch(var/exception/tell_e)
		log_subsystem_persistence_error("Faction beacon: online tell failed: [tell_e]")

	_sweep_unassigned_objects_for_faction(station_zs, faction_uid)

	// A beacon claiming a station should make sure every Z it spans is
	// actually in the persistence save list -- otherwise part of the station
	// it's meant to be anchoring never persists in the first place. It should
	// also grant at least medsec (a faction establishing its own law) on each
	// deck, never downgrading a Z an admin has already set to highsec (Hub law).
	for(var/z in station_zs)
		if(!(z in GLOB.persistence_zlevel_allow))
			SSpersistence.setZLevelPersistence(z, 1, "Faction: [faction_uid]")
		if(zone_security_get(z) < guaranteed_security_tier)
			persistence_set_zone_security(z, guaranteed_security_tier)
		persistence_pin_site_at_z(z, "Faction: [faction_uid]")

	// Extends the security guarantee to nearby overmap sectors within
	// security_radius -- see _apply_security_radius_grant() for the actual
	// range() sweep, also re-run periodically by process() so a site
	// generated or moved into range afterward gets picked up too.
	_apply_security_radius_grant()
	_evict_hazards_in_range()

	// Always refresh the overmap/border visuals on a successful claim,
	// regardless of whether any of the writes above actually changed a
	// tier -- otherwise a beacon whose station (or a covered neighbor) was
	// already at/above its tier when it powered on would flip active=TRUE
	// without ever repainting, and its contribution to the border would
	// silently never appear.
	zone_security_update_overmap()

/// Grants this beacon's guaranteed_security_tier to every overmap sector
/// within security_radius that isn't already at/above it, skipping this
/// beacon's own station Zs and any Z another active beacon already claims.
/// Called once from _apply_network() on activation, and periodically from
/// process() so a site generated or moved into range afterward -- which
/// would otherwise never be swept up until a full power-cycle -- gets
/// picked up within one sweep interval instead. Also diffs the current
/// in-range set against granted_neighbor_zs via _revoke_stale_neighbor_grants()
/// so a Z that falls OUT of range (e.g. a ship that flew off again) gets
/// released too, not just raised and left stuck.
/obj/structure/machinery/faction_beacon/proc/_apply_security_radius_grant()
	if(!SSatlas.current_map.use_overmap || security_radius <= 0)
		_revoke_stale_neighbor_grants(list())
		return
	var/beacon_z = GET_Z(src)
	var/list/station_zs = _station_zs()
	var/obj/effect/overmap/visitable/my_sector = GLOB.map_sectors["[beacon_z]"]
	if(!istype(my_sector))
		_revoke_stale_neighbor_grants(list())
		return
	var/list/current_neighbor_zs = list()
	for(var/obj/effect/overmap/visitable/V in range(security_radius, my_sector))
		for(var/nearby_z in V.map_z)
			if(nearby_z in station_zs)
				continue
			var/obj/structure/machinery/faction_beacon/other = GLOB.faction_beacon_by_z["[nearby_z]"]
			if(other && !QDELETED(other) && other != src)
				continue
			current_neighbor_zs |= nearby_z
			if(zone_security_get(nearby_z) < guaranteed_security_tier)
				persistence_set_zone_security(nearby_z, guaranteed_security_tier)
				zone_security_recheck_mobs_on_z(nearby_z)
	_revoke_stale_neighbor_grants(current_neighbor_zs)

/// Diffs current_neighbor_zs (freshly computed by the caller) against
/// granted_neighbor_zs, and for any z that fell out, falls back to whatever
/// tier is still legitimately justified -- but only if it's still ours to
/// touch: still exactly at guaranteed_security_tier (an admin override, or
/// another beacon since raising it further, leaves a mismatch here and is
/// skipped). The fallback is computed live via _max_tier_from_other_beacons()
/// rather than always dropping to nullsec, so a z still covered by a
/// DIFFERENT, lower-tier beacon lands on that tier directly in one step
/// instead of dipping to nullsec and waiting for that beacon's own next
/// sweep to notice and re-raise it. Pass list() to release everything this
/// beacon has ever granted (deactivating/destroyed, or radius disabled/its
/// sector unresolvable). Always ends by replacing granted_neighbor_zs with
/// current_neighbor_zs.
/obj/structure/machinery/faction_beacon/proc/_revoke_stale_neighbor_grants(list/current_neighbor_zs)
	for(var/z in granted_neighbor_zs)
		if(z in current_neighbor_zs)
			continue
		if(zone_security_get(z) != guaranteed_security_tier)
			continue
		persistence_set_zone_security(z, _max_tier_from_other_beacons(z))
		zone_security_recheck_mobs_on_z(z)
	granted_neighbor_zs = current_neighbor_zs.Copy()

/// Destroys any overmap hazard sitting within this beacon's security_radius.
/// Closes the one gap _overmap_tile_hazard_excluded() (events/event.dm)
/// documents: new encroachment is already blocked (create_events()'s spawn
/// exclusion and handle_move()'s drift redirect), but a hazard already
/// present before the radius claimed its tile -- an older hazard, or a
/// beacon that just powered on/expanded -- was never retroactively evicted.
/// Called alongside _apply_security_radius_grant() so both run on the same
/// activation + periodic-resweep cadence.
/// Shared by _evict_hazards_in_range() and ui_data() so the TGUI can tell
/// command "hazard clearing is currently inactive" apart from "beacon claim
/// is active" instead of silently no-opping behind an active-looking beacon.
/obj/structure/machinery/faction_beacon/proc/_hazard_eviction_active()
	return SSatlas.current_map.use_overmap && security_radius > 0 && guaranteed_security_tier >= ZONE_MEDSEC

/obj/structure/machinery/faction_beacon/proc/_evict_hazards_in_range()
	if(!_hazard_eviction_active())
		return
	var/obj/effect/overmap/visitable/my_sector = GLOB.map_sectors["[GET_Z(src)]"]
	if(!istype(my_sector))
		return
	// .Copy() -- qdel(E) below cascades into update_hazards(T) (event.dm),
	// which removes T from hazard_by_turf once its last hazard is gone.
	// Iterating the live list let that removal shift the next turf into the
	// just-vacated slot, causing this loop to skip it and leave a hazard
	// un-evicted inside an otherwise-secured radius.
	for(var/turf/T in overmap_event_handler.hazard_by_turf.Copy())
		if(get_dist(T, my_sector) > security_radius)
			continue
		for(var/obj/effect/overmap/event/E in overmap_event_handler.hazard_by_turf[T])
			log_game("Faction beacon at ([x],[y],[z]): evicted overmap hazard [E] at ([T.x],[T.y],[T.z]) -- inside secured radius.")
			qdel(E)

/// Claims every UNASSIGNED (persistent_network/req_access_faction/etc.
/// still empty) compatible object across the given Zs for the given
/// faction -- called once by a beacon's _apply_network() when it powers on,
/// periodically by its process() (FACTION_BEACON_SWEEP_INTERVAL) so an
/// object placed AFTER the beacon already went active gets picked up too,
/// and (since this was pulled out of the beacon into a standalone global
/// proc) also by a faction-owned drydock ship on retrieve -- see
/// _drydockRetrieveRun(), persistence_shuttles.dm -- so a faction ship's
/// equipment gets the same one-time auto-claim a station beacon gives its
/// own Zs, just scoped to the ship's Z instead. Never touches anything
/// already assigned, whether to "public", a different faction, this same
/// faction, or (the five crew-tag-compatible types) this Z's ship crew --
/// a manual override (via the tagger, properly authorized) always sticks
/// permanently.
/proc/_sweep_unassigned_objects_for_faction(list/zs, faction_uid)
	var/configured = 0

	try
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(is_type_in_list(pod, GLOB.persistence_cryopod_spawn_ignore))
				continue
			if(!(GET_Z(pod) in zs))
				continue
			if(pod.persistent_network || pod.personal_ckey || pod.crew_tagged)
				continue
			pod.persistent_network = faction_uid
			pod.persistent_spawn   = TRUE
			configured++
	catch(var/exception/cryo_e)
		log_subsystem_persistence_error("Faction sweep: cryopod sweep failed: [cryo_e]")

	try
		for(var/obj/structure/machinery/telepad_cargo/pad in world)
			if(!(GET_Z(pad) in zs))
				continue
			if(pad.persistent_network || pad.personal_ckey || pad.crew_tagged)
				continue
			pad.persistent_network = faction_uid
			pad.persistent_spawn   = TRUE
			pad.faction_shackled   = TRUE
			configured++
	catch(var/exception/pad_e)
		log_subsystem_persistence_error("Faction sweep: telepad sweep failed: [pad_e]")

	// Configure modular computers directly (machine-level persistent_network).
	// Skips handheld PDAs/wristbound computers entirely -- those are personal
	// devices a crew member carries, not station/faction infrastructure.
	try
		for(var/obj/item/modular_computer/MC in world)
			if(!(GET_Z(MC) in zs))
				continue
			if(istype(MC, /obj/item/modular_computer/handheld))
				continue
			if(MC.persistent_network || MC.personal_ckey || MC.crew_tagged)
				continue
			MC.persistent_network = faction_uid
			MC.faction_shackled   = TRUE
			configured++
	catch(var/exception/mc_e)
		log_subsystem_persistence_error("Faction sweep: modular computer sweep failed: [mc_e]")

	try
		for(var/obj/structure/machinery/telecomms/T in world)
			if(!(GET_Z(T) in zs))
				continue
			if(T.persistent_network)
				continue
			T.persistent_network = faction_uid
			configured++
	catch(var/exception/tc_e)
		log_subsystem_persistence_error("Faction sweep: telecomms sweep failed: [tc_e]")

	try
		for(var/obj/structure/machinery/door/airlock/AL in world)
			if(!(GET_Z(AL) in zs))
				continue
			if(AL.req_access_faction || AL.crew_tagged)
				continue
			AL.req_access_faction = faction_uid
			// Clear whatever specific access codes the door had left over
			// from mapping -- otherwise a claimed door could stay locked to
			// the new faction's own members, who have no matching codes.
			// Faction-only access by default; members can tighten it further
			// via the faction tagger's own door-access configuration.
			AL.req_access = null
			AL.req_one_access = null
			configured++
	catch(var/exception/al_e)
		log_subsystem_persistence_error("Faction sweep: airlock sweep failed: [al_e]")

	// Autodocs already have their own persistent_network mechanism
	// (gates medical-system access by faction) but were never actually
	// added to this sweep before -- separate gap from the multi-deck one.
	try
		for(var/obj/structure/machinery/autodoc/AD in world)
			if(!(GET_Z(AD) in zs))
				continue
			if(AD.persistent_network || AD.personal_ckey || AD.crew_tagged)
				continue
			AD.persistent_network = faction_uid
			configured++
	catch(var/exception/ad_e)
		log_subsystem_persistence_error("Faction sweep: autodoc sweep failed: [ad_e]")

	try
		for(var/area/A in GLOB.areas)
			if(!A.is_blueprint_area)
				continue
			if(A.persistent_network)
				continue
			var/on_z = FALSE
			for(var/turf/AT in A.contents)
				if(GET_Z(AT) in zs)
					on_z = TRUE
					break
			if(!on_z)
				continue
			A.persistent_network = faction_uid
			configured++
	catch(var/exception/area_e)
		log_subsystem_persistence_error("Faction sweep: area sweep failed: [area_e]")

	try
		for(var/obj/structure/machinery/porta_turret/PT in world)
			if(!(GET_Z(PT) in zs))
				continue
			if(PT.persistent_network)
				continue
			PT.persistent_network = faction_uid
			configured++
	catch(var/exception/turret_e)
		log_subsystem_persistence_error("Faction sweep: turret sweep failed: [turret_e]")

	if(configured)
		log_game("Faction sweep: networked [configured] object(s)/area(s) to faction '[faction_uid]' across z-level(s) [english_list(zs)].")
	return configured

/// Crew-mode counterpart to _sweep_unassigned_objects_for_faction() -- claims
/// every still-UNASSIGNED (no faction, no personal tag, not already crew-
/// tagged) compatible object across the given Zs for its ship's crew instead
/// of a faction, so a personally-owned drydock ship's owner doesn't have to
/// manually tag every single console by hand on retrieve. Called once by
/// _drydockRetrieveRun() (persistence_shuttles.dm) for a personally-owned
/// ship, mirroring the faction sweep's own one-time _apply_network() call
/// for a faction-owned one. Never touches anything already assigned --
/// same "manual override always sticks" guarantee as the faction sweep.
/proc/_sweep_unassigned_crew(list/zs)
	var/configured = 0

	try
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(is_type_in_list(pod, GLOB.persistence_cryopod_spawn_ignore))
				continue
			if(!(GET_Z(pod) in zs))
				continue
			if(pod.persistent_network || pod.personal_ckey || pod.crew_tagged)
				continue
			pod.crew_tagged = TRUE
			configured++
	catch(var/exception/cryo_e)
		log_subsystem_persistence_error("Crew sweep: cryopod sweep failed: [cryo_e]")

	try
		for(var/obj/structure/machinery/telepad_cargo/pad in world)
			if(!(GET_Z(pad) in zs))
				continue
			if(pad.persistent_network || pad.personal_ckey || pad.crew_tagged)
				continue
			pad.crew_tagged      = TRUE
			pad.persistent_spawn = TRUE // still "accepts deliveries", just keyed to the ship's crew now
			configured++
	catch(var/exception/pad_e)
		log_subsystem_persistence_error("Crew sweep: telepad sweep failed: [pad_e]")

	// Skips handheld PDAs/wristbound computers entirely -- those are personal
	// devices a crew member carries, not ship infrastructure, same exemption
	// the faction sweep applies.
	try
		for(var/obj/item/modular_computer/MC in world)
			if(!(GET_Z(MC) in zs))
				continue
			if(istype(MC, /obj/item/modular_computer/handheld))
				continue
			if(MC.persistent_network || MC.personal_ckey || MC.crew_tagged)
				continue
			MC.crew_tagged = TRUE
			configured++
	catch(var/exception/mc_e)
		log_subsystem_persistence_error("Crew sweep: modular computer sweep failed: [mc_e]")

	try
		for(var/obj/structure/machinery/door/airlock/AL in world)
			if(!(GET_Z(AL) in zs))
				continue
			if(AL.req_access_faction || AL.crew_tagged)
				continue
			AL.crew_tagged = TRUE
			// Clear whatever specific access codes the door had left over
			// from mapping -- same reasoning as the faction sweep's own
			// clear: a crew-tagged door shouldn't stay locked to unrelated
			// map-authored access codes.
			AL.req_access = null
			AL.req_one_access = null
			configured++
	catch(var/exception/al_e)
		log_subsystem_persistence_error("Crew sweep: airlock sweep failed: [al_e]")

	try
		for(var/obj/structure/machinery/autodoc/AD in world)
			if(!(GET_Z(AD) in zs))
				continue
			if(AD.persistent_network || AD.personal_ckey || AD.crew_tagged)
				continue
			AD.crew_tagged = TRUE
			configured++
	catch(var/exception/ad_e)
		log_subsystem_persistence_error("Crew sweep: autodoc sweep failed: [ad_e]")

	if(configured)
		log_game("Crew sweep: crew-tagged [configured] object(s) across z-level(s) [english_list(zs)].")
	return configured

/// Reverses _sweep_unassigned_objects_for_faction() (and any manual Faction Tagger claim
/// that happens to match): clears persistent_network/faction_shackled/
/// req_access_faction back to unassigned on every compatible object/area
/// across this beacon's station currently networked to ITS faction --
/// called alongside the other _release_*() procs wherever this beacon stops
/// being active (powered down, deleted, destroyed). Reuses the exact same
/// vars worldstate already tracks for each type, so the cleared state
/// persists through the normal save path with no new persistence code.
/obj/structure/machinery/faction_beacon/proc/_release_swept_objects()
	var/list/station_zs = _station_zs()
	var/released = 0

	try
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(!(GET_Z(pod) in station_zs))
				continue
			if(pod.persistent_network != faction_uid)
				continue
			pod.persistent_network = ""
			pod.persistent_spawn   = FALSE
			released++
	catch(var/exception/cryo_e)
		log_subsystem_persistence_error("Faction beacon: cryopod release failed: [cryo_e]")

	try
		for(var/obj/structure/machinery/telepad_cargo/pad in world)
			if(!(GET_Z(pad) in station_zs))
				continue
			if(pad.persistent_network != faction_uid)
				continue
			pad.persistent_network = ""
			pad.persistent_spawn   = FALSE
			pad.faction_shackled   = FALSE
			released++
	catch(var/exception/pad_e)
		log_subsystem_persistence_error("Faction beacon: telepad release failed: [pad_e]")

	try
		for(var/obj/item/modular_computer/MC in world)
			if(istype(MC, /obj/item/modular_computer/handheld))
				continue
			if(!(GET_Z(MC) in station_zs))
				continue
			if(MC.persistent_network != faction_uid)
				continue
			MC.persistent_network = ""
			MC.faction_shackled   = FALSE
			released++
	catch(var/exception/mc_e)
		log_subsystem_persistence_error("Faction beacon: modular computer release failed: [mc_e]")

	try
		for(var/obj/structure/machinery/telecomms/T in world)
			if(!(GET_Z(T) in station_zs))
				continue
			if(T.persistent_network != faction_uid)
				continue
			T.persistent_network = ""
			released++
	catch(var/exception/tc_e)
		log_subsystem_persistence_error("Faction beacon: telecomms release failed: [tc_e]")

	try
		for(var/obj/structure/machinery/door/airlock/AL in world)
			if(!(GET_Z(AL) in station_zs))
				continue
			if(AL.req_access_faction != faction_uid)
				continue
			AL.req_access_faction = ""
			// Mirror the sweep's own reset -- an abandoned door reverts to
			// fully open, not stuck with the former faction's custom codes.
			AL.req_access = null
			AL.req_one_access = null
			released++
	catch(var/exception/al_e)
		log_subsystem_persistence_error("Faction beacon: airlock release failed: [al_e]")

	try
		for(var/obj/structure/machinery/autodoc/AD in world)
			if(!(GET_Z(AD) in station_zs))
				continue
			if(AD.persistent_network != faction_uid)
				continue
			AD.persistent_network = ""
			released++
	catch(var/exception/ad_e)
		log_subsystem_persistence_error("Faction beacon: autodoc release failed: [ad_e]")

	try
		for(var/area/A in GLOB.areas)
			if(!A.is_blueprint_area)
				continue
			if(A.persistent_network != faction_uid)
				continue
			var/on_z = FALSE
			for(var/turf/AT in A.contents)
				if(GET_Z(AT) in station_zs)
					on_z = TRUE
					break
			if(!on_z)
				continue
			A.persistent_network = ""
			released++
	catch(var/exception/area_e)
		log_subsystem_persistence_error("Faction beacon: area release failed: [area_e]")

	try
		for(var/obj/structure/machinery/porta_turret/PT in world)
			if(!(GET_Z(PT) in station_zs))
				continue
			if(PT.persistent_network != faction_uid)
				continue
			PT.persistent_network = ""
			released++
	catch(var/exception/turret_e)
		log_subsystem_persistence_error("Faction beacon: turret release failed: [turret_e]")

	if(released)
		log_game("Faction beacon at ([x],[y],[z]): released [released] object(s)/area(s) from faction '[faction_uid]' across z-level(s) [english_list(station_zs)].")
	return released

/obj/structure/machinery/faction_beacon/update_icon()
	icon_state = "bspacerelay"
	// No dedicated "on"/"off" sprite exists yet -- a light glow is a safe,
	// low-risk visual tell that doesn't depend on a sprite frame existing.
	if(active)
		set_light(2, 1, COLOR_CYAN)
	else
		set_light(0)

/// Alt-click toggles the physical lock (mirrors APC/air alarm) -- while
/// locked, the TGUI's power toggle is restricted to admins.
/obj/structure/machinery/faction_beacon/AltClick(mob/user)
	if(!Adjacent(user))
		return
	if(!can_configure_faction_shackle(user, faction_uid, 1))
		to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to (un)lock it."))
		return
	locked = !locked
	playsound(src, locked ? 'sound/machines/terminal/terminal_button03.ogg' : 'sound/machines/terminal/terminal_button01.ogg', 35, FALSE)
	balloon_alert(user, locked ? "locked" : "unlocked")

/obj/structure/machinery/faction_beacon/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	if(locked)
		to_chat(user, SPAN_WARNING("\The [src] is locked."))
		return
	ui_interact(user)

/obj/structure/machinery/faction_beacon/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FactionBeacon", "Faction Beacon", 420, 460)
		ui.open()

/obj/structure/machinery/faction_beacon/ui_data(mob/user)
	var/list/data = list()
	data["faction_uid"] = faction_uid
	data["faction_name"] = faction_uid ? get_faction_name(faction_uid) : null
	data["active"] = active
	data["powered"] = powered
	data["locked"] = locked
	data["anchored"] = anchored
	data["is_admin"] = check_rights(R_ADMIN, 0, user)
	data["can_configure"] = can_configure_faction_shackle(user, faction_uid, 1)
	data["refusal_reason"] = _claim_refusal_reason()
	data["security_radius"] = security_radius
	data["fuel_credits"] = fuel_credits
	data["max_fuel_credits"] = max_fuel_credits
	data["requires_fuel"] = requires_fuel
	data["public_territory"] = public_territory
	// Private only actually restricts entry while raiding is globally
	// disabled -- with it enabled server-wide, every claimed Z is already
	// exterior-accessible by default regardless of this setting. Surfaced so
	// the UI can make that context clear instead of implying Private always
	// blocks non-members.
	data["faction_raiding_enabled"] = GLOB.faction_raiding_enabled
	data["hazard_eviction_active"] = _hazard_eviction_active()
	var/obj/effect/overmap/visitable/here = GLOB.map_sectors["[GET_Z(src)]"]
	data["site_name"] = istype(here) ? here.name : null
	return data

/obj/structure/machinery/faction_beacon/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("toggle_power")
			if(!anchored)
				to_chat(user, SPAN_WARNING("\The [src] must be wrenched to the floor first."))
				return
			if(locked)
				to_chat(user, SPAN_WARNING("\The [src] is locked -- unlock it first (alt-click)."))
				return
			_toggle_power(user)
			. = TRUE
		if("set_faction")
			if(!check_rights(R_ADMIN, 0, user))
				return
			var/new_network = params["uid"]
			var/new_uid = new_network ? normalize_faction_uid(new_network) : null
			if(faction_tagger_set(new_uid, user))
				to_chat(user, SPAN_GOOD("Beacon network set to: [faction_uid ? get_faction_name(faction_uid) : "(none)"][active ? " (active)" : ""]"))
				log_admin("[key_name(user)] force-configured faction beacon at ([x],[y],[z]) to '[faction_uid]' via TGUI.")
			. = TRUE
		if("set_security_radius")
			if(!check_rights(R_ADMIN, 0, user))
				return
			var/radius_input = text2num(params["radius"])
			if(isnull(radius_input))
				return
			var/new_radius = between(0, radius_input, 10)
			security_radius = new_radius
			// Re-run the grant sweep so a live radius increase actually grants
			// the tier to newly-covered neighbor Zs (idempotent -- every check
			// inside only ever writes unset fields), which in turn repaints the
			// overmap border via persistence_set_zone_security(). A decrease
			// also revokes any Z now outside the radius immediately, via
			// _apply_security_radius_grant()'s own _revoke_stale_neighbor_grants()
			// diff against granted_neighbor_zs -- no power-down needed. An
			// inactive beacon never contributes to the border either way, so
			// there's nothing to repaint when it isn't active.
			if(active)
				_apply_network()
			to_chat(user, SPAN_GOOD("Security radius set to [security_radius]."))
			log_admin("[key_name(user)] set faction beacon security radius to [security_radius] at ([x],[y],[z]).")
			. = TRUE
		if("withdraw")
			if(!can_configure_faction_shackle(user, faction_uid, 1))
				return
			if(!requires_fuel)
				return
			var/amount = text2num(params["amount"])
			if(isnull(amount) || amount <= 0)
				return
			amount = min(amount, fuel_credits)
			if(amount <= 0)
				to_chat(user, SPAN_WARNING("No credits to withdraw."))
				return
			fuel_credits -= amount
			var/obj/item/spacecash/bundle/cash = new(get_turf(src))
			cash.worth += amount
			cash.update_icon()
			to_chat(user, SPAN_GOOD("Withdrew [amount] credits."))
			log_game("[key_name(user)] withdrew [amount] fuel credits from a faction beacon at ([x],[y],[z]).")
			. = TRUE
		if("toggle_public_territory")
			if(!can_configure_faction_shackle(user, faction_uid, 1))
				to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to toggle this."))
				return
			public_territory = !public_territory
			to_chat(user, SPAN_GOOD("Territory set to [public_territory ? "PUBLIC" : "PRIVATE"] -- [public_territory ? "non-members may enter regardless of the faction raiding toggle." : "subject to the faction raiding toggle like any other claimed territory."]"))
			log_game("[key_name(user)] set faction beacon at ([x],[y],[z]) territory to [public_territory ? "PUBLIC" : "PRIVATE"].")
			. = TRUE
		if("rename_site")
			if(!can_configure_faction_shackle(user, faction_uid, 1))
				to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to rename this site."))
				return
			var/obj/effect/overmap/visitable/here = GLOB.map_sectors["[GET_Z(src)]"]
			var/new_site_name = tgui_input_text(user, "New overmap name for this site (leave blank to restore the default):", "Rename Site", here ? here.name : "", max_length = 128)
			if(isnull(new_site_name))
				return
			var/refusal = persistence_rename_pinned_site_at_z(GET_Z(src), new_site_name)
			if(refusal)
				to_chat(user, SPAN_WARNING(refusal))
				return
			to_chat(user, SPAN_GOOD("[new_site_name != "" ? "Site renamed to '[new_site_name]'" : "Site name restored to its default"] -- persists across reboots."))
			log_game("[key_name(user)] [new_site_name != "" ? "renamed pinned site to '[new_site_name]'" : "cleared pinned site custom name"] via faction beacon at ([x],[y],[z]).")
			. = TRUE

/// Shared power-toggle body -- used by the TGUI's "toggle_power" action.
/obj/structure/machinery/faction_beacon/proc/_toggle_power(mob/user)
	if(!can_configure_faction_shackle(user, faction_uid, 1))
		to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to toggle it."))
		return

	if(powered)
		_power_down(user, null)
		to_chat(user, SPAN_WARNING("Beacon powered down. Z-level [GET_Z(src)] is now unclaimed, no longer persisted, and its security tier grants released."))
		return

	if(requires_fuel && fuel_credits <= 0)
		to_chat(user, SPAN_WARNING("\The [src] has no fuel credits -- insert spacecash first."))
		return

	powered = TRUE
	_apply_network()
	if(active)
		to_chat(user, SPAN_GOOD("Beacon powered up. Network active."))
	else
		to_chat(user, SPAN_WARNING("Beacon powered up, but could not claim: [_claim_refusal_reason()]."))
	message_admins("[key_name(user)] powered up a faction beacon ([faction_uid ? get_faction_name(faction_uid) : "unconfigured"]) at ([x],[y],[z]). (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")

/// Shared power-down body -- used by _toggle_power() (manual) and the
/// automatic out-of-fuel shutoff in process(). user is null for the
/// automatic case; reason is appended to the admin message either way.
/obj/structure/machinery/faction_beacon/proc/_power_down(mob/user, reason)
	powered = FALSE
	_release_security_grants()
	_release_persistence_save()
	_release_site_pin()
	_release_swept_objects()
	active = FALSE
	_release_z_claim()
	QDEL_NULL(beacon_looping_sound)
	update_icon()
	var/who = user ? key_name(user) : "Automatic"
	message_admins("[who] powered down a faction beacon ([faction_uid ? get_faction_name(faction_uid) : "unconfigured"]) at ([x],[y],[z])[reason ? " -- [reason]" : ""]. (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")

// Faction assignment is configured via the faction tagger tool, or the TGUI's
// admin-only "set_faction" action above (for a "raw" session where nobody has
// a faction ID yet, or admins who don't want to dig out a tagger item) --
// beacon placement itself is still an admin/mapping action.

/// "Break glass" admin access -- the normal TGUI (click to open, toggle_power
/// action) respects `locked` for everyone including admins, by design (a
/// physical lock should mean something). This verb is a separate entry point
/// that never goes through ui_act() at all, so it isn't subject to that gate,
/// for the rare case an admin genuinely needs to override a locked beacon.
/obj/structure/machinery/faction_beacon/verb/admin_override_beacon()
	set name = "Admin: Override Faction Beacon"
	set category = "Admin"
	set desc = "Bypass the lock to check status, toggle power, or force-set the faction network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	to_chat(usr, SPAN_NOTICE("Current: network=[faction_uid ? get_faction_name(faction_uid) : "(none)"] | active=[active] | powered=[powered] | locked=[locked] | anchored=[anchored]"))

	var/action = tgui_input_list(usr, "Select action:", "Admin Override", list("Toggle Power", "Toggle Lock", "Force-Set Faction", "Force-Clear Faction", "Close"))
	if(!action || action == "Close")
		return

	switch(action)
		if("Toggle Power")
			_toggle_power(usr)
		if("Toggle Lock")
			locked = !locked
			to_chat(usr, SPAN_GOOD("Beacon [locked ? "locked" : "unlocked"]."))
			log_admin("[key_name(usr)] [locked ? "locked" : "unlocked"] a faction beacon at ([x],[y],[z]) via admin override.")
		if("Force-Set Faction")
			var/new_network = tgui_input_text(usr, "Enter faction UID (leave blank to clear):", "Force-Set Faction", faction_uid, max_length = 32)
			if(new_network == null)
				return
			var/new_uid = new_network ? normalize_faction_uid(new_network) : null
			if(faction_tagger_set(new_uid, usr))
				to_chat(usr, SPAN_GOOD("Beacon network set to: [faction_uid ? get_faction_name(faction_uid) : "(none)"][active ? " (active)" : ""]"))
				log_admin("[key_name(usr)] force-configured faction beacon at ([x],[y],[z]) to '[faction_uid]' via admin override verb.")
		if("Force-Clear Faction")
			if(faction_tagger_set(null, usr))
				to_chat(usr, SPAN_GOOD("Beacon network cleared."))
				log_admin("[key_name(usr)] force-cleared faction beacon at ([x],[y],[z]) via admin override verb.")

/// Hub-issued variant -- guarantees highsec instead of medsec, visually
/// distinct (bluer tint), and deliberately not purchasable through any
/// player-facing channel (no cargo listing) -- admin-spawn only. Inherits
/// every proc unchanged (TGUI, sweep, lock, wrench) -- only the security
/// tier, default radius, color, and TGUI window title actually differ.
/obj/structure/machinery/faction_beacon/hub
	name = "hub beacon"
	desc = "A Hub-issued anchor beacon that guarantees the highest security tier for the infrastructure it claims."
	color = "#6699ff"
	guaranteed_security_tier = ZONE_HIGHSEC
	security_radius = 2 // reaches further than a standard faction beacon's default of 1
	requires_fuel = FALSE // admin-spawned, immune to the credit maintenance mechanic
	powered = TRUE // admin-spawned, already active -- doesn't need a manual power-on step like a normal beacon

/obj/structure/machinery/faction_beacon/hub/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FactionBeacon", "Hub Beacon", 420, 460)
		ui.open()
