/*
 * Language Primers
 *
 * A cargo-orderable book that teaches its one language to whoever studies it.
 * Ordering is per-language (see code/modules/cargo/items/language_books.dm),
 * so a crate contains exactly the tongue that was paid for.
 *
 * Persistence comes for free: a character's known languages already round-trip
 * through ss13_char_identity.languages_json (charIdentitySaveOne()/
 * applyPersistentIdentityData(), persistence_mobs.dm), so anything learned
 * here survives cryo and reboots with no extra plumbing.
 *
 * Deliberately NOT offered for:
 *   - RESTRICTED languages (Ceti Basic -- which everyone already has --
 *     plus Rootsong, EAL and Noise): innate to a body or a machine, not
 *     something a person studies into existence.
 *   - HIVEMIND languages (Hivenet): a Vaurca biological network, not speech.
 *   - Antagonist and lesser-form languages.
 * What remains is the ordinary spoken/signed set a character could plausibly
 * learn from a book.
 */

/obj/item/book/language_primer
	name = "language primer"
	desc = "A self-study language course. Dense, dry, and surprisingly effective."
	icon_state = "book"
	item_state = "book"
	/// The LANGUAGE_* name this primer teaches. Set on each subtype below.
	var/taught_language

/obj/item/book/language_primer/Initialize()
	. = ..()
	if(taught_language)
		name = "[initial(name)] ([taught_language])"
		desc = "A self-study course in [taught_language]. Dense, dry, and surprisingly effective."

/obj/item/book/language_primer/attack_self(mob/user)
	if(!taught_language)
		return ..()
	if(!ishuman(user))
		to_chat(user, SPAN_WARNING("You can't make sense of \the [src]."))
		return TRUE
	// add_language() is the same call chargen and species grants use, and it
	// already returns FALSE for a language the mob knows -- so this doubles as
	// the "you already speak this" check rather than tracking it separately.
	if(!user.add_language(taught_language))
		to_chat(user, SPAN_NOTICE("You already speak [taught_language]. \The [src] has nothing left to teach you."))
		return TRUE
	user.visible_message(
		SPAN_NOTICE("\The [user] finishes studying \the [src]."),
		SPAN_GOOD("You finish studying \the [src]. You can now speak and understand [taught_language].")
	)
	log_game("[key_name(user)] learned [taught_language] from \a [src].")
	return TRUE

// ---- Freely-spoken tongues ----

/obj/item/book/language_primer/tradeband
	taught_language = LANGUAGE_TRADEBAND

/obj/item/book/language_primer/freespeak
	taught_language = LANGUAGE_GUTTER

/obj/item/book/language_primer/sign
	taught_language = LANGUAGE_SIGN

// ---- Human/Elyran ----

/obj/item/book/language_primer/sol_common
	taught_language = LANGUAGE_SOL_COMMON

/obj/item/book/language_primer/elyran_standard
	taught_language = LANGUAGE_ELYRAN_STANDARD

// ---- Unathi ----

/obj/item/book/language_primer/unathi
	taught_language = LANGUAGE_UNATHI

/obj/item/book/language_primer/azaziba
	taught_language = LANGUAGE_AZAZIBA

// ---- Tajara ----

/obj/item/book/language_primer/siik_maas
	taught_language = LANGUAGE_SIIK_MAAS

/obj/item/book/language_primer/siik_tajr
	taught_language = LANGUAGE_SIIK_TAJR

/obj/item/book/language_primer/nalrasan
	taught_language = LANGUAGE_SIGN_TAJARA

// ---- Skrell ----

/obj/item/book/language_primer/skrellian
	taught_language = LANGUAGE_SKRELLIAN

/obj/item/book/language_primer/yassa
	taught_language = LANGUAGE_YA_SSA

/obj/item/book/language_primer/delvahhi
	taught_language = LANGUAGE_DELVAHII
