/*
 * Piracy Beacon Schematic
 * A reusable blueprint -- most players never see one. Crafts a piracy beacon
 * assembly kit from a bluespace crystal (never cargo-orderable) plus ordinary
 * cargo-orderable steel.
 */

/obj/item/piracy_beacon_schematic
	name = "piracy beacon schematic"
	desc = "A battered, illegally-copied blueprint for assembling a piracy beacon. Doesn't look like standard Hub engineering."
	icon = 'icons/obj/items.dmi'
	icon_state = "paper"
	w_class = WEIGHT_CLASS_TINY

	// CHANGE THIS: crafting is currently a single attack_self() scanning the
	// user's own inventory for the raw materials below, matching the
	// simplest existing deployable_kit examples rather than this codebase's
	// heavier multi-stage frame-assembly pattern (constructable_frame.dm).
	// If piracy beacon construction should later require a workbench, a
	// consumed/one-shot schematic, or additional steps, this proc is where
	// that goes.
	var/required_crystals = 1
	var/required_steel = 10
	var/craft_time = 10 SECONDS

/obj/item/piracy_beacon_schematic/attack_self(mob/user)
	var/obj/item/bluespace_crystal/crystal = locate() in user.get_contents()
	var/obj/item/stack/material/steel/steel = locate() in user.get_contents()

	if(!crystal || !steel || steel.get_amount() < required_steel)
		to_chat(user, SPAN_WARNING("You need [required_crystals] bluespace crystal[required_crystals > 1 ? "s" : ""] and [required_steel] steel to assemble a piracy beacon kit."))
		return

	to_chat(user, SPAN_NOTICE("You start assembling a piracy beacon kit..."))
	if(!do_after(user, craft_time, src, DO_REPAIR_CONSTRUCT))
		return

	// Re-check after the delay -- items may have moved/been used mid-craft.
	if(QDELETED(crystal) || QDELETED(steel) || steel.get_amount() < required_steel)
		to_chat(user, SPAN_WARNING("The materials are no longer available."))
		return

	qdel(crystal)
	steel.use(required_steel)
	var/obj/item/deployable_kit/piracy_beacon/kit = new(user.loc)
	user.visible_message(SPAN_NOTICE("[user] assembles a piracy beacon kit."), SPAN_NOTICE("You assemble a piracy beacon kit."))
	kit.add_fingerprint(user)
