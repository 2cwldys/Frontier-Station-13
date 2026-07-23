/*
 * Android -- a new playable race that is, to any observer, a normal human:
 * same sprites/appearance, same social/legal standing, same human character
 * customization options. Internally, it is built exactly like an IPC
 * (Integrated Positronic Chassis) -- the same organs, "oil" for blood, EMP
 * vulnerability, and roboticist-only repair pipeline -- with a few explicit,
 * deliberate departures from IPC:
 *   - Eats/drinks normally instead of needing external charging (a
 *     biological reactor is hardcoded, not player-selectable -- see
 *     reactor/android in code/modules/organs/internal/species/machine/reactor.dm).
 *   - A free citizen rather than manufactured property: no ownership tag,
 *     Human's nation-state citizenship options instead of IPC's
 *     manufacturer/corporate ones.
 *   - Speech still requires a working voice synthesizer organ, same as IPC
 *     (damage can silence/Gibberish-garble it) -- kept deliberately.
 *   - Immune to DNA scanning/cloning, same as IPC (NO_SCAN, part of the
 *     inherited IS_IPC flag composite) -- kept deliberately.
 *
 * Subtypes /datum/species/machine (IPC's own datum) directly, following the
 * exact "reset visual/mob-type vars back to human" pattern
 * /datum/species/machine/shell (ipc_subspecies.dm) already established and
 * proved out -- built as an independent sibling rather than a subtype of
 * Shell itself, so Android's balance/lore can diverge from Shell's later
 * without dragging Shell along.
 */
/datum/species/machine/android
	name = SPECIES_ANDROID
	short_name = "and"
	name_plural = "Androids"
	category_name = "Android"
	bodytype = BODYTYPE_HUMAN
	species_height = HEIGHT_CLASS_AVERAGE
	height_min = 145
	height_max = 203
	age_min = 18
	age_max = 125
	economic_modifier = 12
	default_genders = list(MALE, FEMALE)
	selectable_pronouns = list(MALE, FEMALE, PLURAL, NEUTER)
	mob_weight = MOB_WEIGHT_MEDIUM

	blurb = "Androids are, externally, completely indistinguishable from baseline humans -- same flesh, same face, same voice. Internally, they are built on the same positronic chassis as an IPC: a metal endoskeleton, oil instead of blood, and systems that only a roboticist can repair. Unlike most IPCs, an Android's reactor is biological -- it eats and drinks like anyone else, and never needs to plug into a charger. Androids are free citizens, not manufactured property, and hold citizenship the same way any human does."

	icobase = 'icons/mob/human_races/human/r_human.dmi'
	deform = 'icons/mob/human_races/ipc/robotic.dmi'
	preview_icon = 'icons/mob/human_races/ipc/shell_preview.dmi' // placeholder -- swap for a dedicated Android preview icon

	light_range = 0
	light_power = 0
	unarmed_types = list(
		/datum/unarmed_attack/punch/ipc,
		/datum/unarmed_attack/stomp/ipc,
		/datum/unarmed_attack/kick/ipc,
		/datum/unarmed_attack/bite
	)

	eyes = "eyes_s"
	show_ssd = "in a deep slumber"

	// Deliberately NOT overriding heat_level_1-3/cold_level_1-3/
	// heat_discomfort_level/body_temperature/passive_temp_gain -- the wide
	// heat/cold tolerance (and dependence on BP_COOLING_UNIT) is an
	// internal/mechanical trait carried straight over from
	// /datum/species/machine, same as IPC's own 600/1200/2400 heat
	// thresholds and near-immunity to cold.
	heat_discomfort_strings = list(
		"Your positronic's temperature probes warn you that you are approaching critical heat levels!",
		"Your cooling systems are struggling to keep your positronic's temperature down!",
		"Your positronic is approaching dangerous temperature levels! Immediate cooling required!",
		"Critical temperature levels approaching!"
		)

	// Human's full customization set (IPC's own defaults omit skin
	// tone/lips/eye color/skin preset entirely) plus HAS_FBP so the medical
	// analyzer treats Android as a normal patient rather than refusing to
	// scan a "non-organic" (mob_helpers.dm's isFBP() check).
	appearance_flags = HAS_HAIR_COLOR | HAS_SKIN_TONE | HAS_EYE_COLOR | HAS_FBP | HAS_SKIN_PRESET | HAS_UNDERWEAR | HAS_SOCKS | HAS_LIPS

	// No BP_IPCTAG -- Android is a free citizen, not owned property (see
	// the check_tag() override and inherent_verbs below).
	has_organ = list(
		BP_BRAIN   = /obj/item/organ/internal/machine/posibrain,
		BP_VOICE_SYNTHESIZER = /obj/item/organ/internal/machine/voice_synthesizer,
		BP_DIAGNOSTICS_SUITE = /obj/item/organ/internal/machine/internal_diagnostics,
		BP_HYDRAULICS = /obj/item/organ/internal/machine/hydraulics,
		BP_ACTUATORS_LEFT = /obj/item/organ/internal/machine/actuators/left,
		BP_ACTUATORS_RIGHT = /obj/item/organ/internal/machine/actuators/right,
		BP_COOLING_UNIT = /obj/item/organ/internal/machine/cooling_unit,
		BP_REACTOR = /obj/item/organ/internal/machine/reactor/android,
		BP_ACCESS_PORT = /obj/item/organ/internal/machine/access_port,
		BP_CELL    = /obj/item/organ/internal/machine/power_core,
		BP_EYES  = /obj/item/organ/internal/eyes/optical_sensor,
	)

	vision_organ = BP_EYES

	has_limbs = list(
		BP_CHEST =  list("path" = /obj/item/organ/external/chest/ipc/android),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin/ipc/android),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/ipc/android),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm/ipc/android),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right/ipc/android),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg/ipc/android),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right/ipc/android),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand/ipc/android),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right/ipc/android),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot/ipc/android),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right/ipc/android)
	)

	// Only the eyes/cooling unit are player-customizable -- the reactor is
	// deliberately NOT alterable, so it always falls back to
	// reactor/android's hardcoded biological default_preset (see that
	// organ's definition) rather than a player picking Electric and ending
	// up needing a charger after all.
	alterable_internal_organs = list(BP_EYES, BP_COOLING_UNIT)

	base_color = "#25032"
	character_color_presets = list("Dark" = "#000000", "Warm" = "#250302", "Cold" = "#1e1e29")

	sprint_temperature_factor = 1.15
	move_charge_factor = 1.1

	// No check_tag verb (no tag organ to check) and no change_monitor verb
	// (that's IPC's monitor-screen-color customization verb -- Android has
	// a human face, not a screen).
	inherent_verbs = list(
		/mob/living/carbon/human/proc/tie_hair)

	bodyfall_sound = SFX_BODYFALL
	use_alt_hair_layer = FALSE
	onfire_overlay = 'icons/mob/burning/burning_human.dmi'

	// Human-like sleep -- lies down, can snore, sleep isn't indefinite --
	// visible/social behavior, kept consistent with "indistinguishable from
	// human," unlike IPC's upright/silent/indefinite "standby" (see the
	// matching sleep_msg()/sleep_examine_msg() overrides below).
	sleeps_upright = FALSE
	snores = TRUE
	indefinite_sleep = FALSE

	// Free citizen -- Human's nation-state citizenship list, not IPC's
	// manufacturer/corporate one.
	possible_cultures = list(
		/singleton/origin_item/culture/biesellite,
		/singleton/origin_item/culture/solarian,
		/singleton/origin_item/culture/dominia,
		/singleton/origin_item/culture/coalition,
		/singleton/origin_item/culture/elyran
	)

/datum/species/machine/android/get_light_color()
	return

/datum/species/machine/android/handle_death(var/mob/living/carbon/human/H)
	return

/// Android carries no BP_IPCTAG organ (free citizen, not owned property) --
/// the inherited /datum/species/machine/check_tag() isn't null-safe against
/// a missing tag organ, so it's overridden to a no-op here rather than
/// inheriting a crash. handle_post_spawn()/before_equip() call this
/// unchanged and don't need their own overrides.
/datum/species/machine/android/check_tag(var/mob/living/carbon/human/new_machine, var/client/player)
	return

/datum/species/machine/android/sleep_msg(var/mob/M)
	M.visible_message(SPAN_NOTICE("[M] falls asleep."))
	to_chat(M, SPAN_NOTICE("You fall asleep."))

/datum/species/machine/android/sleep_examine_msg(var/mob/M)
	return SPAN_NOTICE("[M.get_pronoun("He")] appears to be sleeping.\n")
