/*
	Basically just an empty shell for receiving and broadcasting radio messages. Not
	very flexible, but it gets the job done.
*/

/obj/structure/machinery/telecomms/allinone
	name = "telecommunications mainframe"
	icon_state = "comm_server"
	desc = "A compact machine used for portable subspace telecommuniations processing."
	idle_power_usage = 0
	active_power_usage = 0
	produces_heat = FALSE
	overmap_range = 3
	produces_sound = TRUE

	var/away_aio = FALSE

/obj/structure/machinery/telecomms/allinone/Initialize()
	. = ..()
	if(!freq_listening.len)
		freq_listening = ANTAG_FREQS
	SSmachinery.all_receivers += src

	desc += " It has an effective reception range of [overmap_range] grids on the overmap."

/obj/structure/machinery/telecomms/allinone/Destroy()
	SSmachinery.all_receivers -= src
	return ..()

/obj/structure/machinery/telecomms/allinone/receive_signal(datum/signal/subspace/signal)
	signal.levels = broadcast_levels(signal)

	// Decompress the signal, mark it received
	signal.data["compression"] = 0
	signal.mark_done()

	var/signal_message = "[signal.frequency]:[signal.data["message"]]:[signal.data["realname"]]"
	if(signal_message in GLOB.recent_broadcast_messages)
		return

	GLOB.recent_broadcast_messages += signal_message

	if(signal.data["slow"] > 0)
		addtimer(TYPE_PROC_REF(/datum/signal/subspace, broadcast), signal.data["slow"]) // network lag
	else
		signal.broadcast()

	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(clear_recent_broadcast_message), signal_message), 1 SECONDS)

/obj/structure/machinery/telecomms/allinone/ship
	away_aio = TRUE

// Name/frequency setup lives here rather than LateInitialize() because during
// a fresh drydock deploy the shuttle datum doesn't exist yet when this
// machine's own LateInitialize() runs, so attempt_hook_up() fails there and
// linked stays null; SSshuttle's populate_sector_objects() then links it
// correctly moments later via a DIRECT attempt_hook_up() call that bypasses
// LateInitialize() entirely. Hooking this into attempt_hook_up() itself means
// it fires exactly once, whichever call site is the one that actually
// succeeds -- so the machine never ends up linked-but-listening-on-the-wrong-
// frequency (looks online, never actually relays).
/obj/structure/machinery/telecomms/allinone/ship/attempt_hook_up(obj/effect/overmap/visitable/sector)
	. = ..()
	if(!. || !away_aio)
		return
	if(linked.comms_name)
		name = "[lowertext(linked.comms_name)] [initial(name)]"
	freq_listening = list(
		HAIL_FREQ,
		assign_away_freq(linked.name)
	)

/// Cargo-ordered copy -- starts unanchored so it can be moved out of its
/// crate before being wrenched into place. Mirrors
/// /obj/structure/machinery/ntnet_relay/crate's own shape (NTNet_relay.dm).
/obj/structure/machinery/telecomms/allinone/ship/crate
	anchored = FALSE

// construct_op == 0 (the normal assembled state every placed machine sits
// in) has no existing TOOL_WRENCH case in the base attackby()'s
// deconstruction switch (machine_interactions.dm) -- wrench is only
// meaningful there at construct_op 1/2 (dislodging/re-securing the external
// plating), so this is free to claim for anchoring without disturbing that
// sequence. Falls through to ..() for every other case.
/obj/structure/machinery/telecomms/allinone/ship/crate/attackby(obj/item/attacking_item, mob/user)
	if(construct_op == 0 && attacking_item.tool_behaviour == TOOL_WRENCH)
		if(!attacking_item.tool_use_check(user, 0))
			return
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("You secure \the [src] in place.") : SPAN_NOTICE("You unsecure \the [src]."))
		return
	..()

/obj/structure/machinery/telecomms/allinone/ship/coalition_navy
	name = "coalition navy telecommunications mainframe"
	desc = "A compact machine used for portable subspace telecommuniations processing. This one also has encryption codes for Coalition navy vessels."

// Same reasoning as the base /ship override above -- must react to
// attempt_hook_up() succeeding, not just LateInitialize(), or COAL_FREQ never
// gets added when the hookup only succeeds via the later drydock-deploy path.
/obj/structure/machinery/telecomms/allinone/ship/coalition_navy/attempt_hook_up(obj/effect/overmap/visitable/sector)
	. = ..()
	if(.)
		freq_listening += COAL_FREQ

//This goes on the station map so away ships can maintain radio contact.
/obj/structure/machinery/telecomms/allinone/ship/station_relay
	name = "external signal receiver"
	desc = "This device allows nearby third-party ships to maintain radio contact with their crew that are aboard the %STATIONNAME."
	idle_power_usage = 25
	active_power_usage = 200
	freq_listening = list(HAIL_FREQ)
	away_aio = FALSE

/obj/structure/machinery/telecomms/allinone/ship/station_relay/mechanics_hints(mob/user, distance, is_adjacent)
	. += ..()
	. += "This device does not need to be linked to other telecommunications equipment; it will receive and broadcast on its own. It only needs to be powered."

/obj/structure/machinery/telecomms/allinone/ship/station_relay/LateInitialize()
	. = ..()
	desc = replacetext(desc, "%STATIONNAME", SSatlas.current_map.station_name)
	for(var/ch in AWAY_FREQS_ASSIGNED)
		freq_listening |= AWAY_FREQS_ASSIGNED[ch]
	freq_listening |= AWAY_FREQS_UNASSIGNED
	freq_listening |= ANTAG_FREQS

/obj/structure/machinery/telecomms/allinone/ship
