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

/obj/structure/machinery/telecomms/allinone/ship/LateInitialize()
	. = ..()
	if(!linked)
		return

	if(away_aio)
		if(linked.comms_name)
			name = "[lowertext(linked.comms_name)] [initial(name)]"
		freq_listening = list(
			HAIL_FREQ,
			assign_away_freq(linked.name)
		)

/obj/structure/machinery/telecomms/allinone/ship/coalition_navy
	name = "coalition navy telecommunications mainframe"
	desc = "A compact machine used for portable subspace telecommuniations processing. This one also has encryption codes for Coalition navy vessels."

/obj/structure/machinery/telecomms/allinone/ship/coalition_navy/LateInitialize()
	. = ..()
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
