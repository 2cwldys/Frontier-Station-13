/*
 * Organ Bioprinter
 * Grows replacement organs from stored biomass, matched to whichever species'
 * blood sample is currently loaded. The /prosthetics variant instead prints a
 * fixed, species-independent set of robotic organs/limbs from stored metal.
 */

/obj/structure/machinery/bioprinter
	name = "organ bioprinter"
	desc = "It's a machine that grows replacement organs."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "bioprinter"

	anchored = 1
	density = 1
	idle_power_usage = 40

	var/prints_prosthetics
	var/stored_matter = 200
	var/max_stored_matter = 500

	/// Species ID (matches GLOB.all_species' own key, S.name) resolved from a
	/// loaded blood sample's donor at the moment it's loaded -- never trust
	/// the blood sample's own "species" key directly, since that stores the
	/// species' bodytype string, not its name, and GLOB.all_species is keyed
	/// by name. Persisted; loaded_species itself is re-resolved from this on
	/// both boot and restore, since a species datum isn't itself JSON-safe.
	var/loaded_species_id
	var/loaded_blood_type
	var/loaded_blood_dna
	/// Runtime-only, resolved from loaded_species_id.
	var/datum/species/loaded_species

	/// Cached product list, keyed by the organ's own display name (e.g.
	/// "heart"). Rebuilt whenever a new sample is loaded and after a
	/// worldstate restore -- never persisted directly, it's fully derived.
	var/list/products = list()

	/// The display key (from products) currently mid-print, or null if idle.
	var/print_job
	var/print_delay = 10 SECONDS
	/// In-memory only, deliberately absent from worldstate_vars -- matches
	/// this codebase's own established convention that in-progress
	/// world.time-relative timers are never persisted; a restored printer
	/// always comes back idle, never mid-print.
	var/time_print_end = 0

	component_types = list(
		/obj/item/circuitboard/bioprinter,
		/obj/item/stock_parts/matter_bin,
		/obj/item/stock_parts/manipulator
	)

/obj/structure/machinery/bioprinter/crate
	anchored = FALSE

/obj/structure/machinery/bioprinter/prosthetics
	name = "prosthetics fabricator"
	desc = "It's a machine that prints prosthetic organs."
	prints_prosthetics = 1

	component_types = list(
		/obj/item/circuitboard/bioprinter/prosthetics,
		/obj/item/stock_parts/matter_bin,
		/obj/item/stock_parts/manipulator
	)

/obj/structure/machinery/bioprinter/Initialize(mapload)
	. = ..()
	products = get_possible_products()

/obj/structure/machinery/bioprinter/RefreshParts()
	..()
	var/bin_rating = 0
	var/man_rating = 0
	for(var/obj/item/stock_parts/P in component_parts)
		if(ismatterbin(P))
			bin_rating += P.rating
		else if(ismanipulator(P))
			man_rating += P.rating
	max_stored_matter = initial(max_stored_matter) * max(1, bin_rating)
	print_delay = initial(print_delay) / max(1, man_rating)

/obj/structure/machinery/bioprinter/update_icon()
	if(print_job && icon_exists(icon, "[initial(icon_state)]-working"))
		icon_state = "[initial(icon_state)]-working"
	else
		icon_state = initial(icon_state)

/// Flesh printer: species-aware, derived from whichever species' blood
/// sample is currently loaded. Filters loaded_species' own has_organ/
/// has_limbs type lists through organ_type_is_printable().
/obj/structure/machinery/bioprinter/proc/get_possible_products()
	. = list()
	if(!loaded_species)
		return
	var/list/organs = list()
	for(var/tag in loaded_species.has_organ)
		organs += loaded_species.has_organ[tag]
	for(var/tag in loaded_species.has_limbs)
		organs += loaded_species.has_limbs[tag]["path"]
	for(var/organtype in organs)
		if(!organ_type_is_printable(organtype))
			continue
		var/obj/item/organ/O = organtype
		var/cost = initial(O.print_cost) || round(0.75 * initial(O.max_damage))
		.[initial(O.name)] = list(O, cost)
	return .

/// Prosthetics fabricator: a fixed, species-independent list -- a robotic
/// replacement doesn't vary by species, and deliberately bypasses
/// organ_type_is_printable()'s vital/overkill-heal filters (a robotic heart
/// or arm replacement is exactly the point, even though those flags would
/// otherwise exclude them from the flesh printer's own list).
/obj/structure/machinery/bioprinter/prosthetics/get_possible_products()
	. = list()
	var/list/organs = list(
		/obj/item/organ/internal/heart,
		/obj/item/organ/internal/lungs,
		/obj/item/organ/internal/kidneys,
		/obj/item/organ/internal/eyes,
		/obj/item/organ/internal/liver,
		/obj/item/organ/internal/stomach,
		/obj/item/organ/external/arm,
		/obj/item/organ/external/arm/right,
		/obj/item/organ/external/leg,
		/obj/item/organ/external/leg/right,
		/obj/item/organ/external/hand,
		/obj/item/organ/external/hand/right,
		/obj/item/organ/external/foot,
		/obj/item/organ/external/foot/right
	)
	for(var/organtype in organs)
		var/obj/item/organ/O = organtype
		var/cost = initial(O.print_cost) || round(0.75 * initial(O.max_damage))
		.[initial(O.name)] = list(O, cost)
	return .

/obj/structure/machinery/bioprinter/proc/_load_blood_sample(list/blood_data, mob/user)
	var/datum/weakref/W = blood_data["donor"]
	var/mob/living/carbon/donor = W?.resolve()
	var/resolved_species_id
	if(istype(donor) && donor.species)
		resolved_species_id = donor.species.name
	if(!resolved_species_id || !GLOB.all_species[resolved_species_id])
		to_chat(user, SPAN_WARNING("\The [src] can't identify a living species from this sample."))
		return
	loaded_species_id = resolved_species_id
	loaded_species = GLOB.all_species[loaded_species_id]
	loaded_blood_type = blood_data["blood_type"]
	loaded_blood_dna = blood_data["blood_DNA"]
	products = get_possible_products()
	to_chat(user, SPAN_NOTICE("You inject the blood sample into \the [src]. It identifies the donor as [loaded_species.name]."))

/obj/structure/machinery/bioprinter/proc/_start_print(choice, mob/user)
	if(print_job)
		to_chat(user, SPAN_WARNING("\The [src] is already printing something."))
		return
	if(!(choice in products))
		return
	var/list/entry = products[choice]
	var/cost = entry[2]
	if(stored_matter < cost)
		to_chat(user, SPAN_WARNING("There is not enough matter in \the [src]."))
		return
	stored_matter -= cost
	print_job = choice
	time_print_end = world.time + print_delay
	update_icon()

/obj/structure/machinery/bioprinter/proc/_cancel_print(mob/user)
	if(!print_job)
		return
	var/list/entry = products[print_job]
	if(entry)
		stored_matter = min(max_stored_matter, stored_matter + entry[2])
	print_job = null
	time_print_end = 0
	update_icon()
	if(user)
		to_chat(user, SPAN_NOTICE("You cancel the print job."))

/obj/structure/machinery/bioprinter/proc/_finish_print()
	var/list/entry = products[print_job]
	print_job = null
	time_print_end = 0
	update_icon()
	if(!entry)
		return
	var/organtype = entry[1]
	var/obj/item/organ/O = new organtype(get_turf(src))
	if(prints_prosthetics)
		O.robotize() // Overwrites status wholesale -- must run before ORGAN_CUT_AWAY is set below.
	O.status |= ORGAN_CUT_AWAY
	visible_message(SPAN_NOTICE("\The [src] spits out a new organ."))

/obj/structure/machinery/bioprinter/process()
	if(!print_job)
		return
	if(world.time >= time_print_end)
		_finish_print()

/obj/structure/machinery/bioprinter/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	ui_interact(user)

/obj/structure/machinery/bioprinter/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Bioprinter", name)
		ui.open()

/obj/structure/machinery/bioprinter/ui_data(mob/user)
	var/list/data = list()
	data["prints_prosthetics"] = prints_prosthetics
	data["stored_matter"] = stored_matter
	data["max_stored_matter"] = max_stored_matter
	data["print_job"] = print_job
	data["print_seconds_left"] = print_job ? max(0, round((time_print_end - world.time) / 10)) : 0
	data["print_delay_seconds"] = round(print_delay / 10)
	data["loaded_species_name"] = loaded_species ? loaded_species.name : null
	data["loaded_blood_type"] = loaded_blood_type
	data["loaded_blood_dna"] = loaded_blood_dna
	var/list/product_list = list()
	for(var/pname in products)
		var/list/entry = products[pname]
		product_list += list(list("name" = pname, "cost" = entry[2]))
	data["products"] = product_list
	return data

/obj/structure/machinery/bioprinter/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(action == "print")
		_start_print(params["choice"], usr)
		. = TRUE
	else if(action == "cancel")
		_cancel_print(usr)
		. = TRUE

/obj/structure/machinery/bioprinter/attackby(obj/item/attacking_item, mob/user)
	if(default_deconstruction_screwdriver(user, attacking_item))
		return TRUE
	if(default_deconstruction_crowbar(user, attacking_item))
		return TRUE
	if(default_part_replacement(user, attacking_item))
		return TRUE

	// DNA sample from syringe.
	if(!prints_prosthetics && istype(attacking_item, /obj/item/reagent_containers/syringe))
		var/obj/item/reagent_containers/syringe/S = attacking_item
		var/list/blood_data = REAGENT_DATA(S.reagents, /singleton/reagent/blood)
		if(!blood_data)
			to_chat(user, SPAN_WARNING("\The [attacking_item] has no blood sample loaded."))
			return TRUE
		if(print_job)
			to_chat(user, SPAN_WARNING("\The [src] is busy printing -- wait for it to finish before loading a new sample."))
			return TRUE
		_load_blood_sample(blood_data, user)
		S.reagents.clear_reagents()
		return TRUE
	// Meat for biomass.
	if(!prints_prosthetics && istype(attacking_item, /obj/item/reagent_containers/food/snacks/meat))
		if(stored_matter >= max_stored_matter)
			to_chat(user, SPAN_WARNING("\The [src] is full."))
			return TRUE
		stored_matter = min(max_stored_matter, stored_matter + 50)
		user.drop_from_inventory(attacking_item, src)
		to_chat(user, SPAN_NOTICE("\The [src] processes \the [attacking_item]. Levels of stored biomass now: [stored_matter]"))
		qdel(attacking_item)
		return TRUE
	// Steel for matter.
	if(prints_prosthetics && istype(attacking_item, /obj/item/stack/material) && attacking_item.get_material_name() == DEFAULT_WALL_MATERIAL)
		if(stored_matter >= max_stored_matter)
			to_chat(user, SPAN_WARNING("\The [src] is full."))
			return TRUE
		var/obj/item/stack/S = attacking_item
		stored_matter = min(max_stored_matter, stored_matter + (S.amount * 10))
		user.drop_from_inventory(attacking_item, src)
		to_chat(user, SPAN_NOTICE("\The [src] processes \the [attacking_item]. Levels of stored matter now: [stored_matter]"))
		qdel(attacking_item)
		return TRUE

	return ..()
