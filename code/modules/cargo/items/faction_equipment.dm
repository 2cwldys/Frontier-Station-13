/**
 * Faction-exclusive cargo equipment.
 *
 * Everything in this file is declared the same way any other cargo item is --
 * they simply also set `restricted_to_faction` (cargo_items.dm), which makes
 * them invisible to, and unorderable from, any console not shackled to one of
 * the named factions. Both the listing and the order path enforce it, via
 * _can_order_faction_item() (cargo_order.dm).
 *
 * `tag_spawned_to_faction` tags spawned pieces to the ordering faction on
 * delivery through the item's own faction_tagger_set() -- so armour and helmets
 * arrive already marked and wearing the faction's colour, without a tagger pass
 * by hand. `faction_finish_types` (set on the base below) narrows that to the
 * armour and helmet specifically, leaving the rest of a kit at its normal
 * appearance.
 *
 * Add a new faction's kit by adding a singleton here. Nothing else needs
 * touching: no registry, no subsystem edit, no UI change.
 */

/// Shared base for faction-only equipment. Exists purely so a declaration below
/// reads as "this is faction gear" at a glance and the common properties live
/// in one place -- it adds no behaviour of its own beyond the defaults.
/singleton/cargo_item/faction_restricted
	supplier = "Hub"
	access = 0
	container_type = "crate"
	/// Faction kit is a full loadout in one box; mixing it with unrelated
	/// orders in a shared crate makes for a confusing delivery.
	groupable = FALSE
	spawn_amount = 1
	/// Faction gear arrives marked as that faction's property by default.
	tag_spawned_to_faction = TRUE
	/// ...but only the armour and helmet actually wear the faction's mark and
	/// colour. Tagging every taggable piece meant a kit's gloves, shoes,
	/// balaclava, gas mask, goggles, uniform, and satchel all came out recoloured
	/// too, which is not what "faction-marked gear" is meant to look like.
	faction_finish_types = list(
		/obj/item/clothing/suit/armor,
		/obj/item/clothing/head/helmet
	)

/singleton/cargo_item/faction_restricted/hub_lancer
	category = "security"
	name = "Hub Lancer equipment crate"
	description = "A complete Lancer loadout: hardened carrier and lancer helmet, carbine with armour-piercing magazines, uniform, sidearm belt, and field kit. Restricted to Hub personnel."
	price = 45000
	restricted_to_faction = "hub"
	items = list(
		// Armour -- tagged to Hub on delivery along with everything else
		// taggable in this list.
		/obj/item/clothing/suit/armor/carrier/lance,
		/obj/item/clothing/head/helmet/riot/lancer,

		// Primary
		/obj/item/gun/projectile/automatic/rifle/carbine,

		// Uniform
		/obj/item/clothing/under/rank/lance,
		/obj/item/clothing/accessory/armband/sec,
		/obj/item/clothing/gloves/combat,
		/obj/item/clothing/shoes/combat,

		// Field kit
		/obj/item/storage/backpack/satchel/sec,
		/obj/item/modular_computer/handheld/pda/security,
		/obj/item/commander_beacon,

		// Sidearm and optics
		/obj/item/storage/belt/security/full/pistol45,
		/obj/item/clothing/glasses/safety/goggles/goon/pmc,
		/obj/item/clothing/mask/balaclava,

		/obj/item/clothing/mask/gas/tactical,

		/obj/item/radio/headset/headset_sec
	)

/// The carbine's magazines, as a separate entry purely so four of them can be
/// delivered without listing the typepath four times -- spawn_amount multiplies
/// EVERYTHING in an item's own `items` list, so they cannot ride along with the
/// loadout above without quadrupling the whole crate.
/singleton/cargo_item/faction_restricted/hub_lancer_magazines
	category = "security"
	name = "Hub Lancer carbine magazines"
	description = "Four armour-piercing magazines for the Lancer's carbine. Restricted to Hub personnel."
	price = 6000
	restricted_to_faction = "hub"
	container_type = "box"
	items = list(
		/obj/item/ammo_magazine/a556/carbine/ap
	)
	spawn_amount = 4
