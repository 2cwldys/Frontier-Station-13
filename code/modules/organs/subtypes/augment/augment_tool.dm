/obj/item/organ/internal/augment/tool
	name = "retractable widget"
	action_button_name = "Deploy Widget"
	cooldown = 10
	activable = TRUE
	var/obj/item/augment_type
	var/aug_slot = slot_r_hand
	// Overrides the base augment class' list (augment.dm) to add Android --
	// otherwise identical. Android is a /datum/species/machine subtype like
	// every IPC chassis brand and has the same normal humanoid hand slots,
	// but the base list predates Android's addition to the codebase and
	// never got it added.
	species_restricted = list(
		SPECIES_HUMAN_OFFWORLD,
		SPECIES_HUMAN,
		SPECIES_IPC_BISHOP,
		SPECIES_IPC_G1,
		SPECIES_IPC_G2,
		SPECIES_IPC_SHELL,
		SPECIES_IPC_XION,
		SPECIES_IPC_ZENGHU,
		SPECIES_IPC,
		SPECIES_ANDROID,
		SPECIES_SKRELL_AXIORI,
		SPECIES_SKRELL,
		SPECIES_TAJARA_MSAI,
		SPECIES_TAJARA_ZHAN,
		SPECIES_TAJARA,
		SPECIES_UNATHI,
	)

/obj/item/organ/internal/augment/tool/attack_self(var/mob/user)
	. = ..()

	if(!.)
		return FALSE

	if(!augment_type)
		return FALSE

	if (locate(augment_type) in owner)
		var/obj/slot_item = locate(augment_type) in owner
		owner.drop_from_inventory(slot_item)
		qdel(slot_item)
		owner.visible_message(
			SPAN_NOTICE("\The [slot_item] slides back into \the [owner]'s [owner.organs_by_name[parent_organ]]."),
			SPAN_NOTICE("You retract \the [slot_item]!")
		)
		return

	if (owner.get_equipped_item(aug_slot))
		to_chat(owner, SPAN_WARNING("Something is stopping you from enabling your [src]!"))
		return

	var/obj/item/M = new augment_type(owner)
	M.canremove = FALSE
	M.item_flags |= ITEM_FLAG_NO_MOVE
	owner.equip_to_slot(M, aug_slot)
	var/obj/item/organ/O = owner.organs_by_name[parent_organ]

	//If we didn't found the organ, it might be a sub-organ, search for it
	if(!O)
		for(var/external_organ_key in owner.organs_by_name)
			var/obj/item/organ/external/external_organ = owner.organs_by_name[external_organ_key]
			for(var/obj/item/organ/internal/internal_organ in external_organ.internal_organs)
				if(internal_organ.organ_tag == parent_organ)
					O = internal_organ
					break

	//If we have found it, print the message, otherwise don't bother, it would just runtime
	if(O)
		owner.visible_message(
			SPAN_NOTICE("\The [M] slides out of \the [owner]'s [O.name]."),
			SPAN_NOTICE("You deploy \the [M]!")
		)
