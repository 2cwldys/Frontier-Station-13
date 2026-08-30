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

	/// Faction UID this fabricator is tagged to, or "" for unrestricted.
	/// Same tagger interface the clone pod/resleever use (resleever_cloning.dm)
	/// -- only relevant to the "IPC Body" print job below, which is the only
	/// product that costs credits rather than just stored matter.
	var/persistent_network = ""
	/// ckey this fabricator is personally tagged to, or null. Mutually
	/// exclusive with persistent_network.
	var/personal_ckey = null
	var/personal_char_name = null
	/// Set for the print-delay window between starting an IPC Body print and
	/// it finishing -- holds who to refund if the job is canceled, since
	/// credits (unlike stored_matter) aren't tracked in the generic
	/// products/print_job vars. Null whenever no IPC Body print is in
	/// progress.
	var/list/ipc_body_billing = null
	worldstate_vars = list("persistent_network", "personal_ckey", "personal_char_name")

/obj/structure/machinery/bioprinter/prosthetics/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/bioprinter/prosthetics/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/bioprinter/prosthetics/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	personal_ckey = null
	personal_char_name = null
	return TRUE

/obj/structure/machinery/bioprinter/prosthetics/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/structure/machinery/bioprinter/prosthetics/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	persistent_network = ""
	return TRUE

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
		/obj/item/organ/external/foot/right,
		/obj/item/organ/internal/neural_lace
	)
	for(var/organtype in organs)
		var/obj/item/organ/O = organtype
		var/cost = initial(O.print_cost) || round(0.75 * initial(O.max_damage))
		.[initial(O.name)] = list(O, cost)
	// Not an organ at all -- a blank IPC chassis to resleeve into, the
	// synthetic counterpart to the clone pod's organic growth. entry[1] is
	// null and specially handled by _finish_print() below rather than
	// instantiated as an organ type. entry[3] is the credit cost on top of
	// the matter cost -- 0/absent for every organ above.
	.["IPC Body"] = list(null, IPC_BODY_MATTER_COST, IPC_BODY_CREDIT_COST)
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

/obj/structure/machinery/bioprinter/prosthetics/proc/resolve_ipc_body_billing(mob/living/user)
	var/tag_uid = normalize_faction_uid(persistent_network)
	if(tag_uid && get_effective_faction_rank(user, tag_uid) >= 0)
		return list("faction" = tag_uid)
	return list("personal" = TRUE)

/// Charges IPC_BODY_CREDIT_COST via faction_debit() or the user's own
/// account -- same shape as the clone pod's _charge_clone_fee()
/// (resleever_cloning.dm), but always charged regardless of
/// CLONING_COSTS_CREDITS (see that define's own doc comment).
/obj/structure/machinery/bioprinter/prosthetics/proc/_charge_ipc_body_fee(faction_uid, mob/living/user)
	PRIVATE_PROC(TRUE)
	var/reason = "IPC chassis print"
	if(faction_uid)
		if(!faction_debit(faction_uid, IPC_BODY_CREDIT_COST, reason))
			to_chat(user, SPAN_WARNING("[get_faction_name(faction_uid)] cannot cover the [IPC_BODY_CREDIT_COST] credit chassis fee."))
			return FALSE
		return TRUE
	var/obj/item/card/id/ID = user.GetIdCard()
	if(!ID || !ID.associated_account_number)
		to_chat(user, SPAN_WARNING("No bank account found on your ID."))
		return FALSE
	var/datum/money_account/account = SSeconomy.get_account(ID.associated_account_number)
	if(!account || account.suspended)
		to_chat(user, SPAN_WARNING("Your account is unavailable."))
		return FALSE
	if(account.money < IPC_BODY_CREDIT_COST)
		to_chat(user, SPAN_WARNING("You cannot afford the [IPC_BODY_CREDIT_COST] credit chassis fee."))
		return FALSE
	SSeconomy.charge_to_account(ID.associated_account_number, "[src]", reason, "[src]", -IPC_BODY_CREDIT_COST)
	return TRUE

/// Reverses _charge_ipc_body_fee() -- fires when an in-progress IPC Body
/// print is canceled (_cancel_print() override below). Refunds to whoever
/// originally paid (ipc_body_billing), not necessarily whoever cancels.
/obj/structure/machinery/bioprinter/prosthetics/proc/_refund_ipc_body_fee(faction_uid, mob/living/user)
	PRIVATE_PROC(TRUE)
	var/reason = "IPC chassis print refund"
	if(faction_uid)
		faction_credit(faction_uid, IPC_BODY_CREDIT_COST, reason)
		return
	var/obj/item/card/id/ID = user?.GetIdCard()
	if(ID && ID.associated_account_number)
		SSeconomy.charge_to_account(ID.associated_account_number, "[src]", reason, "[src]", IPC_BODY_CREDIT_COST)

/// IPC Body is the one product that costs credits on top of stored matter --
/// resolve billing, confirm, and charge BEFORE handing off to the shared
/// matter-deduct/timer-start logic (..()), so a declined/unaffordable charge
/// never reserves matter in the first place. Every other product falls
/// straight through to the base proc unchanged.
/obj/structure/machinery/bioprinter/prosthetics/_start_print(choice, mob/living/user)
	if(choice != "IPC Body")
		return ..()
	if(print_job)
		to_chat(user, SPAN_WARNING("\The [src] is already printing something."))
		return
	var/list/entry = products[choice]
	if(!entry || stored_matter < entry[2])
		to_chat(user, SPAN_WARNING("There is not enough matter in \the [src]."))
		return

	var/list/billing = resolve_ipc_body_billing(user)
	var/faction_uid = billing["faction"]
	var/payer_desc = faction_uid ? get_faction_name(faction_uid) : "your personal account"
	if(tgui_alert(user, "Print a blank IPC chassis for [IPC_BODY_CREDIT_COST] credits and [entry[2]] matter, billed to [payer_desc]?", "Print IPC Body", list("Print", "Cancel")) != "Print")
		return

	// Re-check after the prompt -- state can change while it sits open.
	if(print_job || stored_matter < entry[2])
		to_chat(user, SPAN_WARNING("\The [src]'s state changed while you were deciding. Aborting."))
		return
	if(!_charge_ipc_body_fee(faction_uid, user))
		return

	ipc_body_billing = list("faction" = faction_uid, "user" = user)
	..()

/// Refunds the credit charge too when the canceled job was an IPC Body --
/// the shared logic below only ever refunds stored_matter.
/obj/structure/machinery/bioprinter/prosthetics/_cancel_print(mob/user)
	var/was_ipc_body = (print_job == "IPC Body")
	var/list/billing = ipc_body_billing
	. = ..()
	if(was_ipc_body && billing)
		_refund_ipc_body_fee(billing["faction"], billing["user"])
	ipc_body_billing = null

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

/// IPC Body finishes as a blank, unconscious synthetic body instead of an
/// organ item -- the synthetic counterpart to
/// build_cloned_body_for_character() (resleever_cloning.dm), minus any
/// chargen/character lookup: the body carries no identity until a neural
/// lace is manually resleeved into it. Can't fall through to ..() at all --
/// entry[1] is null for this product, not an organ type to instantiate.
/obj/structure/machinery/bioprinter/prosthetics/_finish_print()
	if(print_job != "IPC Body")
		return ..()
	print_job = null
	time_print_end = 0
	ipc_body_billing = null
	update_icon()
	var/mob/living/carbon/human/shell = new(get_turf(src))
	shell.set_species(SPECIES_IPC)
	shell.real_name = "unclaimed synthetic chassis"
	shell.name = shell.real_name
	shell.set_stat(UNCONSCIOUS)
	visible_message(SPAN_NOTICE("\The [src] extrudes a blank synthetic chassis."))

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
		product_list += list(list("name" = pname, "cost" = entry[2], "credit_cost" = length(entry) >= 3 ? entry[3] : 0))
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

#undef IPC_BODY_CREDIT_COST
#undef IPC_BODY_MATTER_COST
