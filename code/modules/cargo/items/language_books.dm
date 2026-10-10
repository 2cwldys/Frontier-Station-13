/*
 * Language primers -- one cargo entry per language, so a crate contains
 * exactly the tongue that was paid for. The books themselves (and the reasons
 * some languages are deliberately not offered) live in
 * code/modules/library/language_primer.dm.
 *
 * Priced in two tiers: widely-spoken trade tongues are cheap and unrestricted,
 * species languages cost more since they're a genuine cultural asset rather
 * than a commodity.
 */

/// Abstract, or the singleton repo instantiates this parent too and registers
/// it under its own inherited name ("generic cargo item", cargo_items.dm) with
/// an empty items list -- SScargo keys the catalogue by name (cargo.dm), so a
/// bogus entry like that both appears for sale and silently collides with
/// anything else sharing that name.
ABSTRACT_TYPE(/singleton/cargo_item/language_primer)
/singleton/cargo_item/language_primer
	category = "science"
	supplier = "Hub"
	price = 2500
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

// ---- Trade tongues ----

/singleton/cargo_item/language_primer/tradeband
	name = "language primer - Tradeband"
	description = "A self-study course in Tradeband, the lingua franca of Sol's commercial corridors."
	items = list(/obj/item/book/language_primer/tradeband)

/singleton/cargo_item/language_primer/freespeak
	name = "language primer - Freespeak"
	description = "A self-study course in Freespeak, the loose creole of the frontier and its less reputable ports."
	items = list(/obj/item/book/language_primer/freespeak)

/singleton/cargo_item/language_primer/sign
	name = "language primer - Sign Language"
	description = "An illustrated self-study course in standard sign language."
	items = list(/obj/item/book/language_primer/sign)

// ---- Human and Elyran ----

/singleton/cargo_item/language_primer/sol_common
	name = "language primer - Sol Common"
	description = "A self-study course in Sol Common, the working tongue of the Sol Alliance."
	items = list(/obj/item/book/language_primer/sol_common)

/singleton/cargo_item/language_primer/elyran_standard
	name = "language primer - Elyran Standard"
	description = "A self-study course in Elyran Standard, as taught in the Republic's own schools."
	items = list(/obj/item/book/language_primer/elyran_standard)

// ---- Unathi ----

/singleton/cargo_item/language_primer/unathi
	name = "language primer - Sinta'unathi"
	description = "A self-study course in Sinta'unathi. Includes a pronunciation guide for throats that lack the hardware."
	price = 25000
	items = list(/obj/item/book/language_primer/unathi)

/singleton/cargo_item/language_primer/azaziba
	name = "language primer - Sinta'azaziba"
	description = "A self-study course in Sinta'azaziba, the gestural tongue of the Izweski hegemony's southern clans."
	price = 25000
	items = list(/obj/item/book/language_primer/azaziba)

// ---- Tajara ----

/singleton/cargo_item/language_primer/siik_maas
	name = "language primer - Siik'maas"
	description = "A self-study course in Siik'maas, the most widely spoken tongue of Adhomai."
	price = 25000
	items = list(/obj/item/book/language_primer/siik_maas)

/singleton/cargo_item/language_primer/siik_tajr
	name = "language primer - Siik'tajr"
	description = "A self-study course in Siik'tajr, the tail-and-ear cant of Adhomai."
	price = 25000
	items = list(/obj/item/book/language_primer/siik_tajr)

/singleton/cargo_item/language_primer/nalrasan
	name = "language primer - Nal'rasan"
	description = "An illustrated self-study course in Nal'rasan, the signed language of Adhomai."
	price = 25000
	items = list(/obj/item/book/language_primer/nalrasan)

// ---- Skrell ----

/singleton/cargo_item/language_primer/skrellian
	name = "language primer - Nral'Malic"
	description = "A self-study course in Nral'Malic. Comes with a warning about the strain on unadapted vocal cords."
	price = 25000
	items = list(/obj/item/book/language_primer/skrellian)

/singleton/cargo_item/language_primer/yassa
	name = "language primer - Ya'ssa"
	description = "A self-study course in Ya'ssa, spoken among the Skrell's Ya'ssa-speaking communities."
	price = 25000
	items = list(/obj/item/book/language_primer/yassa)

/singleton/cargo_item/language_primer/delvahhi
	name = "language primer - Delvahhi"
	description = "A self-study course in Delvahhi."
	price = 25000
	items = list(/obj/item/book/language_primer/delvahhi)
