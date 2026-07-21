/mob/living/simple_animal/hostile/gutslug
	name = "gutslug"
	desc = "A vicious little creature, its teeth are razor sharp."
	icon = 'icons/mob/npc/gutslug.dmi'
	icon_state = "gutslug"
	icon_living = "gutslug"
	icon_dead = "gutslug_dead"
	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "stamps on"
	destroy_surroundings = 1
	health = 20
	maxhealth = 20
	speed = 10
	density = FALSE
	mob_size = MOB_TINY
	melee_damage_lower = 3
	melee_damage_upper = 6
	faction = "asteroid"
	attack_sound = 'sound/weapons/bite.ogg'
	attacktext = "bitten"
	attack_vis_effect = ATTACK_EFFECT_BITE

	// Asteroid-dwelling -- unaffected by vacuum/atmos, same exemption its cult variant below already needs.
	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0

	tameable = FALSE

/mob/living/simple_animal/hostile/gutslug/Allow_Spacemove(check_drift = 0)
	return 1 // no floating in zero-g, same exemption as GREED/space carp

/// Hunts every player on the same Z-level, not just ones seen/heard -- an
/// asteroid ambush predator, not a sighted one.
/mob/living/simple_animal/hostile/gutslug/get_targets(dist)
	var/list/found = list()
	for(var/mob/living/carbon/human/H in GLOB.mob_list)
		if(H.z == z)
			found += H
	return found

/// Never loses track of a target just because line-of-sight breaks mid-chase.
/mob/living/simple_animal/hostile/gutslug/see_target(atom/target)
	return TRUE

/// Burrows into H -- pierces a breach through a worn space suit first (if
/// any), then embeds directly into the chest organ via this codebase's own
/// embed()/wound system, same as any other embedded object: requires
/// surgery to safely remove.
/mob/living/simple_animal/hostile/gutslug/proc/attach(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/S = H.get_covering_equipped_item_by_zone(BP_CHEST)
	if(istype(S) && S.can_breach)
		S.create_breaches(DAMAGE_BRUTE, 20)
		if(!length(S.breaches)) // couldn't punch a hole in it, give up
			return
	var/obj/item/organ/external/chest = H.organs_by_name[BP_CHEST]
	if(!chest)
		return
	var/obj/item/holder/gutslug/holder = new(get_turf(src))
	src.forceMove(holder)
	chest.embed(holder, FALSE, "\The [src] latches itself onto \the [H]!")

/mob/living/simple_animal/hostile/gutslug/AttackingTarget()
	. = ..()
	if(istype(., /mob/living/carbon/human))
		var/mob/living/carbon/human/H = .
		if(H.getBruteLoss() > 30 && prob(H.getBruteLoss() / 4))
			attach(H)

/obj/item/holder/gutslug
	name = "gutslug"
	no_name = TRUE
