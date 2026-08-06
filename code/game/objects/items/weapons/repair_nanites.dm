/**
 * Repair Nanites -- the consumable for the item durability system's lower repair
 * tier: tops an item back up to full condition, but refuses anything already
 * broken (that needs nanopaste, which is the only thing that clears wear_broken).
 *
 * This exists because the durability system originally borrowed /obj/item/tape_roll
 * for the job. That type is the game's duct tape and dates to the Initial commit --
 * it also tapes eyes/mouths/hands, glues bones in surgery, makes splints, sticks
 * paper and builds the improvised pipe gun, and it shares its display name with the
 * unrelated /obj/item/taperoll (police tape). Giving repairs their own item hands
 * duct tape back its original identity and ends that name collision.
 *
 * See /obj/item/attackby() in code/game/objects/items.dm for the repair branch.
 */
/obj/item/repairnanites
	name = "repair nanites"
	desc = "A sealed cartridge of maintenance nanites. Applied to worn equipment, they knit \
			the damage back out of it -- though they can do nothing for something already broken."
	desc_extended = "Repair nanites restore worn gear to full condition, but lack the reconstructive \
					capability of nanopaste and will not revive equipment that has failed outright."
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "nano_mani"
	w_class = WEIGHT_CLASS_TINY
	drop_sound = 'sound/items/drop/component.ogg'
	pickup_sound = 'sound/items/pickup/component.ogg'
	origin_tech = list(TECH_MATERIAL = 4, TECH_ENGINEERING = 3)
	// Cannot go into a bag. /obj/item/storage/attackby() calls the parent for its
	// side effects, discards the result, and inserts the item regardless -- so
	// applying a cartridge to a container repaired it, consumed the cartridge,
	// and then stored the consumed cartridge, duplicating it. Refusing storage
	// outright closes that off.
	can_enter_storage = FALSE
