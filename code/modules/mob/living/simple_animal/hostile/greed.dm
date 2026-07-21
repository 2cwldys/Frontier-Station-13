/mob/living/simple_animal/hostile/greed
	name = "GREED" // never uncapitalize GREED
	desc = "A sanity-destroying otherthing."
	speak_emote = list("gibbers")
	icon = 'icons/mob/npc/greed.dmi'
	icon_state = "greed"
	icon_living = "greed"
	icon_dead = "greed_dead"
	health = 60
	maxhealth = 60
	speed = 12
	destroy_surroundings = 1

	melee_damage_lower = 20
	melee_damage_upper = 30
	attacktext = "chomped"
	attack_vis_effect = ATTACK_EFFECT_BITE
	attack_sound = 'sound/weapons/bite.ogg'

	faction = "asteroid"

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

	meat_amount = 10
	meat_type = /obj/item/reagent_containers/food/snacks/meat

	tameable = FALSE

/mob/living/simple_animal/hostile/greed/Allow_Spacemove(check_drift = 0)
	return 1 // Ripped from space carp, no floating in zero-g

/// Hunts every player on the same Z-level, not just ones seen/heard -- an
/// asteroid ambush predator, not a sighted one.
/mob/living/simple_animal/hostile/greed/get_targets(dist)
	var/list/found = list()
	for(var/mob/living/carbon/human/H in GLOB.mob_list)
		if(H.z == z)
			found += H
	return found

/// Never loses track of a target just because line-of-sight breaks mid-chase.
/mob/living/simple_animal/hostile/greed/see_target(atom/target)
	return TRUE

/mob/living/simple_animal/hostile/greed/cult
	faction = "cult"
	supernatural = 1
	appearance_flags = NO_CLIENT_COLOR

/mob/living/simple_animal/hostile/greed/cult/cultify()
	return
