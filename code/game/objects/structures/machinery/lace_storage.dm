/*
 * Lace Storage Pod
 * Holds an extracted neural lace containing a player's consciousness.
 * Can be networked to a faction or public, similar to cryopods.
 * Uncollected laces auto-transfer here after 10 minutes.
 */

/obj/structure/machinery/lace_storage
	name = "lace storage pod"
	desc = "A storage pod for preserved neural lace consciousness units."
	icon = 'icons/obj/machinery/cryopod.dmi'
	icon_state = "lace_pod_empty"
	anchored = TRUE
	density = TRUE

	/// Faction UID, "public", or "" (unmanaged)
	var/persistent_network = ""
	/// Neural lace stored in this pod
	var/obj/item/organ/internal/neural_lace/stored_lace = null
	/// ckey of the stored consciousness (for reconnect routing)
	var/stored_ckey = ""

/obj/structure/machinery/lace_storage/Initialize()
	. = ..()
	update_icon()

/obj/structure/machinery/lace_storage/update_icon()
	if(stored_lace)
		icon_state = "lace_pod_occupied"
	else
		icon_state = "lace_pod_empty"

/obj/structure/machinery/lace_storage/examine(mob/user)
	. = ..()
	if(stored_lace)
		. += SPAN_NOTICE("The pod contains [stored_lace.registered_name]'s neural lace.")
		if(stored_lace.lace_mob)
			. += SPAN_ITALIC("A faint presence can be felt within.")
	else
		. += SPAN_NOTICE("The pod is empty.")

/obj/structure/machinery/lace_storage/attack_hand(mob/user)
	// Allow extraction of the stored lace by hand
	if(stored_lace && Adjacent(user))
		user.put_in_hands(stored_lace)
		stored_lace = null
		stored_ckey = ""
		update_icon()
		to_chat(user, SPAN_NOTICE("You carefully remove the neural lace from the storage pod."))

/obj/structure/machinery/lace_storage/verb/configure_lace_network()
	set name = "Configure Lace Storage Network"
	set category = "Persistence"
	set desc = "Set this pod's faction network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	var/new_network = tgui_input_text(usr, "Enter network ID ('public', a faction UID, or leave blank to clear):", "Configure Lace Storage", persistent_network, max_length = 32)
	if(new_network == null) return

	persistent_network = new_network
	to_chat(usr, SPAN_GOOD("Lace storage network set to: [persistent_network ? persistent_network : "(unmanaged)"]"))
	log_admin("[key_name(usr)] configured lace storage at ([x],[y],[z]) network='[persistent_network]'")

/obj/structure/machinery/lace_storage/worldstate_get_content()
	if(!persistent_network && !stored_ckey)
		return list()
	return list("network" = persistent_network, "stored_ckey" = stored_ckey)

/obj/structure/machinery/lace_storage/worldstate_apply_content(list/content)
	persistent_network = content["network"] || ""
	stored_ckey = content["stored_ckey"] || ""
	update_icon()

/// Find an available lace storage pod for the given faction (or public)
/proc/persistence_find_lace_storage(faction_uid = null)
	// Priority 1: faction pod
	if(faction_uid)
		for(var/obj/structure/machinery/lace_storage/pod in world)
			if(is_station_level(pod.z) && pod.persistent_network == faction_uid && !pod.stored_lace)
				return pod
	// Priority 2: public pod
	for(var/obj/structure/machinery/lace_storage/pod in world)
		if(is_station_level(pod.z) && pod.persistent_network == "public" && !pod.stored_lace)
			return pod
	return null
